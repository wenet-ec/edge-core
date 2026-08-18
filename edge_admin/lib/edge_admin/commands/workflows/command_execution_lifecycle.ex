# edge_admin/lib/edge_admin/commands/workflows/command_execution_lifecycle.ex
defmodule EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle do
  @moduledoc """
  Owns command-execution state transitions and agent-facing lifecycle workflows.

  This includes agent acknowledgements and results, cancellation, dropping
  executions when a node is removed, and the atomic status-transition backstop
  used by distributed Admin instances. Time-based expiration and pruning live
  in EdgeAdmin.Commands.Workflows.Retention.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.AdminGateway.Router, as: GatewayRouter
  alias EdgeAdmin.AdminGateway.Worker, as: GatewayWorker
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Commands.Checks
  alias EdgeAdmin.Commands.Forms
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  require Logger

  @type dropped_command_execution :: %{
          execution: CommandExecution.t(),
          command: Command.t(),
          cluster_name: String.t()
        }

  @doc "Marks pending or sent executions for a node as dropped during node cleanup."
  @spec drop_node_command_executions(String.t(), String.t()) :: [dropped_command_execution()]
  def drop_node_command_executions(node_id, cluster_name) do
    executions =
      Repo.all(
        from(ce in CommandExecution,
          where: ce.node_id == ^node_id,
          where: ce.status in [:pending, :sent],
          preload: [:command]
        )
      )

    dropped =
      executions
      |> Enum.reduce([], fn execution, acc ->
        case transition_status(execution, [:pending, :sent], status: :dropped) do
          {:ok, updated_execution} ->
            [%{execution: updated_execution, command: execution.command, cluster_name: cluster_name} | acc]

          {:error, :stale_state} ->
            acc
        end
      end)
      |> Enum.reverse()

    if dropped != [] do
      :telemetry.execute(
        [:edge_admin, :commands, :execution, :dropped],
        %{count: length(dropped)},
        %{}
      )
    end

    dropped
  end

  @doc "Publishes events for executions dropped during node cleanup."
  @spec publish_dropped_command_executions([dropped_command_execution()]) :: :ok
  def publish_dropped_command_executions(dropped_command_executions) do
    Enum.each(dropped_command_executions, fn %{execution: execution, command: command, cluster_name: cluster_name} ->
      Events.publish(%Catalog.CommandExecutionDropped{
        execution: execution,
        command: command,
        cluster_name: cluster_name
      })
    end)

    :ok
  end

  @doc """
  Acknowledges command execution receipt from agent.

  Validates execution is in `:pending` status and transitions it to `:sent`.
  Called when agent receives and stores a pending command execution.

  ## Parameters
  - `execution` - The execution struct
  - `params` - Currently unused; accepted for symmetry with the controller surface.
    Pass `%{}` from new call sites.

  ## Returns
  - `{:ok, execution}` - Acknowledgment succeeded
  - `{:error, {:conflict, reason}}` - Execution not in `:pending` status
  - `{:error, changeset}` - Status update failed validation

  ## Examples

      iex> acknowledge_command_execution(execution, %{})
      {:ok, %CommandExecution{status: :sent}}
  """
  @spec acknowledge_command_execution(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, Ecto.Changeset.t()}
  def acknowledge_command_execution(execution, _params) do
    with :ok <- Checks.CommandExecutionPendingCheck.check(execution),
         {:ok, updated} <-
           transition_status(execution, [:pending],
             status: :sent,
             sent_at: DateTime.truncate(DateTime.utc_now(), :second)
           ) do
      publish_execution_event(updated, :sent)
      {:ok, updated}
    else
      {:error, :stale_state} ->
        # Row moved out of :pending between the check and the write — surface
        # the same 409 the check would have produced if it had won the race.
        {:error, {:conflict, "execution is no longer in 'pending' status and cannot be acknowledged"}}

      other ->
        other
    end
  end

  @doc """
  Updates command execution result from agent.

  Validates execution status and updates with the agent-reported result. A
  valid result from the authenticated owning Agent may finalize a `:pending`
  row because the result proves delivery even when Admin missed the delivery
  acknowledgement. The agent is the source of truth for terminal status: an
  `exit_code: 143` (SIGTERM) is rewritten to `:cancelled`, an agent-reported
  `status: :expired` passes through, and everything else is recorded as
  `:completed`.

  ## Parameters
  - `execution` - The execution struct
  - `params` - Map with:
    - `"status"` (required) — `"completed"` or `"expired"` (wire-format string from agent)
    - `"output"` (optional) — command stdout/stderr text
    - `"exit_code"` (optional) — integer; 143 forces cancelled, 124 categorised as timeout
    - `"completed_at"` (optional) — ISO 8601 datetime; defaults to now

  ## Returns
  - `{:ok, execution}` - Update succeeded
  - `{:error, changeset}` - Validation failed
  - `{:error, {:conflict, reason}}` - Execution not in a state that accepts a result
  """
  @spec update_command_execution_result(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def update_command_execution_result(execution, params) do
    with :ok <- Checks.CommandExecutionAcceptsResultCheck.check(execution),
         {:ok, attrs} <- Forms.UpdateCommandExecutionResultForm.changeset(params) do
      terminal_status =
        cond do
          attrs["exit_code"] == 143 -> :cancelled
          attrs["status"] == :expired -> :expired
          true -> :completed
        end

      # Conditional transition: only write if the row is still in a state that
      # accepts a result. The race-window allowance from
      # `CommandExecutionAcceptsResultCheck` (cancelled/expired with nil exit_code) is
      # encoded directly in the WHERE clause so two concurrent reports cannot
      # both succeed and clobber each other.
      result = transition_to_result(execution, build_result_set(attrs, terminal_status))

      case result do
        {:ok, updated_execution} ->
          duration_ms =
            if execution.sent_at do
              DateTime.diff(DateTime.utc_now(), execution.sent_at, :millisecond)
            else
              0
            end

          exit_code_category =
            cond do
              updated_execution.exit_code == 0 -> :success
              updated_execution.exit_code == 143 -> :cancelled
              updated_execution.exit_code == 124 -> :timeout
              updated_execution.exit_code > 0 -> :failure
              true -> :unknown
            end

          :telemetry.execute(
            [:edge_admin, :commands, :execution, :completed],
            %{duration: duration_ms},
            %{exit_code_category: exit_code_category}
          )

          event_type = if terminal_status == :cancelled, do: :cancelled, else: :completed
          publish_execution_event(updated_execution, event_type)

        _ ->
          :ok
      end

      case result do
        {:error, :stale_state} ->
          # Row was already in a terminal-with-exit_code state by the time we
          # tried to write. Treat as a 409 — the agent has already reported a
          # result (possibly via a different admin) and should not retry.
          {:error, {:conflict, "execution is no longer in a state that accepts a result (likely already reported)"}}

        other ->
          other
      end
    end
  end

  # Build the `update_all set:` keyword list from the form-normalised attrs
  # map. The form guarantees `completed_at` is a %DateTime{} and that
  # `output`/`exit_code` are either present-with-a-value or absent.
  defp build_result_set(attrs, terminal_status) do
    base = [
      status: terminal_status,
      completed_at: DateTime.truncate(attrs["completed_at"], :second)
    ]

    base
    |> maybe_put(:output, Map.get(attrs, "output"))
    |> maybe_put(:exit_code, Map.get(attrs, "exit_code"))
    |> maybe_put(
      :cancelled_at,
      terminal_status == :cancelled && DateTime.truncate(DateTime.utc_now(), :second)
    )
  end

  defp maybe_put(set, _key, nil), do: set
  defp maybe_put(set, _key, false), do: set
  defp maybe_put(set, key, value), do: Keyword.put(set, key, value)

  @doc """
  Cancels a command execution.

  Handles two scenarios:
  1. Pending — Updates DB status to `:cancelled` immediately (command never
     reached the agent, no output / exit code).
  2. Sent — Sends best-effort cancellation request to agent via Gateway. The
     row's status is left as `:sent` until the agent reports back (which may
     be `:cancelled` or, if the agent already finished, `:completed`).

  ## Parameters
    - execution: CommandExecution struct (must be preloaded with :cluster)

  ## Returns
    - `{:ok, {:cancelled, execution}}` — pending branch, DB updated
    - `{:ok, :accepted}` — sent branch, agent accepted the cancellation request
    - `{:error, {:conflict, reason}}` — execution not in cancellable state
    - `{:error, :service_unavailable}` — agent unreachable (sent branch only)
  """
  @spec cancel_command_execution(CommandExecution.t()) ::
          {:ok, {:cancelled, CommandExecution.t()} | :accepted}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def cancel_command_execution(execution) do
    with :ok <- Checks.CommandExecutionCancellableCheck.check(execution) do
      case execution.status do
        :pending ->
          # Conditional cancel: only flip pending → cancelled. If a peer admin
          # or this admin's scheduler moved the row to :sent in the meantime,
          # fall through to the :sent branch and ask the agent to cancel.
          #
          # Every status transition on a CommandExecution flows through one of the two
          # helpers below. The point is to make each transition a single atomic SQL
          # statement (`UPDATE ... WHERE id = ? AND status IN (...)`) so that stale
          # in-memory structs can never overwrite a row that has moved on.
          #
          # Background: this code path runs on every admin in a multi-admin cluster,
          # and ownership of an edge cluster can flap during reconciliation. Without a
          # WHERE-status guard, two admins delivering the same execution (or a single
          # admin whose HTTP round trip is slow enough for the agent to round-trip a
          # result back) can clobber a terminal row back to :sent / :expired. See the
          # incident write-up in the changelog.
          case transition_status(execution, [:pending],
                 status: :cancelled,
                 cancelled_at: DateTime.truncate(DateTime.utc_now(), :second)
               ) do
            {:ok, updated} ->
              publish_execution_event(updated, :cancelled)
              {:ok, {:cancelled, Repo.preload(updated, [:command, :cluster])}}

            {:error, :stale_state} ->
              case Repo.get(CommandExecution, execution.id) do
                %CommandExecution{status: :sent} = current ->
                  cancel_sent_execution(current)

                _ ->
                  {:error, {:conflict, "execution is no longer cancellable"}}
              end
          end

        :sent ->
          cancel_sent_execution(execution)
      end
    end
  end

  @doc "Conditionally transitions an execution from one of the allowed statuses."
  @spec transition_status(CommandExecution.t(), [CommandExecution.status()], keyword()) ::
          {:ok, CommandExecution.t()} | {:error, :stale_state}
  def transition_status(%CommandExecution{id: id}, allowed_from, set) do
    where = dynamic([ce], ce.status in ^allowed_from)
    do_transition(id, where, set)
  end

  # Result-report transition. The "accepts a result" predicate is dynamic:
  # :pending (Agent result proves delivery even if Admin missed the delivery
  # acknowledgement) OR :sent (normal) OR :cancelled / :expired with
  # exit_code IS NULL (race-window placeholders).
  #
  # Paired predicate: the same rule is encoded as a pure struct check in
  # `EdgeAdmin.Commands.Checks.CommandExecutionAcceptsResultCheck`, which runs first
  # as the layer-3 early-409 gate. This dynamic is the layer-4/5 backstop
  # against concurrent writers the struct check cannot see (peer admin races,
  # agent retries hitting a different admin). If you change the predicate
  # here, change the check there too — the two layers must agree.
  @spec transition_to_result(CommandExecution.t(), keyword()) ::
          {:ok, CommandExecution.t()} | {:error, :stale_state}
  defp transition_to_result(%CommandExecution{id: id}, set) do
    accepts_result =
      dynamic(
        [ce],
        ce.status in [:pending, :sent] or
          (ce.status in [:cancelled, :expired] and is_nil(ce.exit_code))
      )

    do_transition(id, accepts_result, set)
  end

  # Shared core. Runs a conditional `update_all` on the row, and on exactly 1
  # row affected, fetches the fresh struct for event publication. `updated_at`
  # is appended automatically; callers pass only the fields they want to set.
  #
  # We do a follow-up `Repo.get` rather than `update_all returning: [:*]`
  # because the SQLite adapter (DB_ADAPTER=sqlite) does not support RETURNING
  # on `update_all`. Two round trips, identical semantics on both adapters.
  defp do_transition(id, where_dynamic, set) do
    set = Keyword.put(set, :updated_at, DateTime.truncate(DateTime.utc_now(), :second))

    query =
      from(ce in CommandExecution,
        where: ce.id == ^id,
        where: ^where_dynamic
      )

    case Repo.update_all(query, set: set) do
      {1, _} ->
        case Repo.get(CommandExecution, id) do
          nil -> {:error, :stale_state}
          fresh -> {:ok, Repo.preload(fresh, :command)}
        end

      {0, _} ->
        {:error, :stale_state}
    end
  end

  # Extracted shared :sent-branch cancel for use from `cancel_command_execution/1`
  # both directly (when called with a :sent row) and from the fall-through when a
  # :pending row raced to :sent between the check and our conditional update.
  defp cancel_sent_execution(execution) do
    case send_cancel_to_agent(execution) do
      :ok ->
        {:ok, :accepted}

      {:error, reason} ->
        Logger.warning("Failed to send cancellation to agent for execution #{execution.id}: #{inspect(reason)}")

        {:error, :service_unavailable}
    end
  end

  @doc "Sends a best-effort cancellation request to the owning agent."
  def send_cancel_to_agent(execution) do
    with {:ok, node} <- Nodes.get_node(execution.node_id),
         node_name = Node.node_name(node),
         {:ok, cluster_name, _admin_name} <- Metadata.find_node_cluster(node_name),
         {:ok, gateway} <- GatewayRouter.resolve(cluster_name),
         :ok <- GatewayWorker.cancel_execution(gateway, node, execution.id) do
      Logger.info("Successfully sent cancellation request to agent for execution #{execution.id}")

      :ok
    else
      {:error, :not_found} ->
        Logger.error("Node not found for execution #{execution.id}")
        {:error, :node_not_found}

      {:error, :gateway_not_found} ->
        Logger.error("Gateway not found for node #{execution.node_id}")
        {:error, :gateway_not_found}

      {:error, :no_owner} ->
        Logger.error("No owner found for node #{execution.node_id}")
        {:error, :no_owner}

      {:error, reason} ->
        Logger.warning("Failed to send cancellation to agent for execution #{execution.id}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  def publish_execution_event(execution, type) do
    execution = Repo.preload(execution, [:command, node: :cluster], force: true)
    cluster_name = execution.node && execution.node.cluster && execution.node.cluster.name

    event =
      case type do
        :sent ->
          %Catalog.CommandExecutionSent{execution: execution, command: execution.command, cluster_name: cluster_name}

        :completed ->
          %Catalog.CommandExecutionCompleted{
            execution: execution,
            command: execution.command,
            cluster_name: cluster_name
          }

        :cancelled ->
          %Catalog.CommandExecutionCancelled{
            execution: execution,
            command: execution.command,
            cluster_name: cluster_name
          }

        :expired ->
          %Catalog.CommandExecutionExpired{
            execution: execution,
            command: execution.command,
            cluster_name: cluster_name
          }
      end

    Events.publish(event)
  end
end
