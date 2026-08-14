# edge_admin/lib/edge_admin/commands/workflows/retention.ex
defmodule EdgeAdmin.Commands.Workflows.Retention do
  @moduledoc """
  Owns time-based command-execution retention.

  Expiration handles commands that outlive their configured deadline. Pruning
  removes finalized execution history after the configured retention period.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Commands.Enums.CommandExecutionStatuses
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Repo

  require Logger

  @doc """
  Expires all stale command executions whose command's `expires_at` has passed.

  Called by the Quantum scheduler (every minute). Processes executions in two passes:

  - `pending` - Command never reached the agent; mark expired immediately in DB.
  - `sent` - Command was delivered; send best-effort cancellation to agent, then mark
    expired in DB regardless of whether the agent acknowledged it. If the agent already
    ran the command and reports back later, `CommandExecutionAcceptsResultCheck` will accept the
    result and overwrite the expired status (agent is source of truth for what ran).

  Always returns `:ok` — errors are logged but never halt the scheduler.
  """
  @spec expire_stale_command_executions() :: :ok
  def expire_stale_command_executions do
    now = DateTime.utc_now()

    # Scope to clusters owned by this admin. Without this gate, every admin in
    # the fleet runs the expiration loop against every cluster every minute,
    # producing write amplification and (pre-conditional-update) clobbering
    # terminal rows. Mirrors the ownership gate in `deliver_local_command_executions/0`.
    my_cluster_names =
      Metadata.get_my_clusters()
      |> Map.keys()
      |> Enum.map(&String.replace_prefix(&1, "cluster-", ""))

    stale_executions =
      if my_cluster_names == [] do
        []
      else
        get_stale_executions(now, my_cluster_names)
      end

    if Enum.empty?(stale_executions) do
      Logger.debug("No stale executions to expire")
      :ok
    else
      Logger.info("Expiring #{length(stale_executions)} stale execution(s)")

      Enum.each(stale_executions, fn execution ->
        case execution.status do
          :pending ->
            expire_execution(execution, now)

          :sent ->
            # Best-effort cancel signal to agent — do not block on result
            case CommandExecutionLifecycle.send_cancel_to_agent(execution) do
              :ok ->
                Logger.debug("Sent cancellation to agent for expiring execution #{execution.id}")

              {:error, reason} ->
                Logger.warning(
                  "Could not reach agent for expiring execution #{execution.id}: #{inspect(reason)} — marking expired anyway"
                )
            end

            expire_execution(execution, now)
        end
      end)

      :telemetry.execute(
        [:edge_admin, :commands, :expiration],
        %{expired_count: length(stale_executions)},
        %{}
      )

      :ok
    end
  end

  defp get_stale_executions(now, cluster_names) do
    cancellable = CommandExecutionStatuses.cancellable_statuses()

    Repo.all(
      from(ce in CommandExecution,
        join: c in assoc(ce, :command),
        join: n in assoc(ce, :node),
        join: cl in assoc(n, :cluster),
        where: ce.status in ^cancellable,
        where: not is_nil(c.expires_at),
        where: c.expires_at <= ^now,
        where: cl.name in ^cluster_names,
        preload: [node: :cluster, command: []]
      )
    )
  end

  defp expire_execution(execution, _now) do
    # Conditional transition: only expire rows still in :pending or :sent. If
    # the agent has already reported back (row is now :completed/:cancelled/
    # :expired with exit_code), do not overwrite — the agent is the source of
    # truth for what actually ran.
    case CommandExecutionLifecycle.transition_status(execution, [:pending, :sent], status: :expired) do
      {:ok, updated} ->
        Logger.info("Execution #{execution.id} marked expired")
        CommandExecutionLifecycle.publish_execution_event(updated, :expired)

      {:error, :stale_state} ->
        Logger.debug(
          "Skipped expire transition for execution #{execution.id}: row already left :pending/:sent (agent reported back)"
        )
    end
  end

  @prune_batch_size 1_000

  @doc """
  Deletes finalised command executions older than `retention_days`.

  An execution is considered finalised — meaning it can no longer receive any
  updates — when:

    * `status in [:completed, :dropped]`, or
    * `status in [:cancelled, :expired]` AND `exit_code IS NOT NULL` (agent
      reported the result of the cancel/expire signal).

  A `:cancelled` or `:expired` row with `nil exit_code` is NOT finalised — it's
  a race-window placeholder that `CommandExecutionAcceptsResultCheck` still accepts a
  late agent report for (the agent picked the command up before the admin's
  cancel/expire reached it). Pruning those would lose the agent's actual
  result if it eventually arrived. We exclude them, regardless of age.

  In-flight executions (`:pending`, `:sent`) are never deleted.

  Deletes in batches of #{@prune_batch_size} to avoid long locks on the hot path.
  Returns `{:ok, total_deleted}`.
  """
  @spec prune_command_executions(pos_integer()) :: {:ok, non_neg_integer()}
  def prune_command_executions(retention_days) when is_integer(retention_days) and retention_days > 0 do
    cutoff = DateTime.shift(DateTime.utc_now(), day: -retention_days)
    total = prune_loop(cutoff, 0)
    {:ok, total}
  end

  defp prune_loop(cutoff, acc) do
    # Load eligible rows (with command + cluster preloaded for the event) so we
    # can fire `command_execution.pruned` per row before deletion. Then delete
    # by ID. The two-step is intentional: the only async-deletion path in this
    # codebase is pruning, and consumers maintaining state mirrors have no
    # other way to learn that a row went away.
    #
    # Eligibility: completed/dropped (always finalised), OR cancelled/expired with
    # exit_code set (agent reported back). Excludes the cancel/expire race
    # window where exit_code is still nil.
    eligible =
      Repo.all(
        from(ce in CommandExecution,
          where:
            ce.inserted_at < ^cutoff and
              (ce.status in [:completed, :dropped] or
                 (ce.status in [:cancelled, :expired] and not is_nil(ce.exit_code))),
          limit: @prune_batch_size,
          preload: [:command, node: :cluster]
        )
      )

    case eligible do
      [] ->
        acc

      rows ->
        Enum.each(rows, &enqueue_pruned_event/1)

        ids = Enum.map(rows, & &1.id)
        {deleted, _} = Repo.delete_all(from(ce in CommandExecution, where: ce.id in ^ids))

        if deleted == @prune_batch_size do
          prune_loop(cutoff, acc + deleted)
        else
          acc + deleted
        end
    end
  end

  defp enqueue_pruned_event(execution) do
    cluster_name = execution.node && execution.node.cluster && execution.node.cluster.name

    Events.publish(%Catalog.CommandExecutionPruned{
      execution: execution,
      command: execution.command,
      cluster_name: cluster_name
    })
  end
end
