# edge_admin/lib/edge_admin/admins/syn_event_handler.ex
defmodule EdgeAdmin.Admins.SynEventHandler do
  @moduledoc """
  Syn event handler bridge for admin topology changes.

  Implements the `:syn_event_handler` behaviour so that syn calls our callbacks
  whenever a process joins or leaves a group on any node in the cluster.

  ## What we care about

  We use two syn scopes:

  - `:admin_scope` — process group where each admin joins with its metadata.
    Join/leave here means an admin instance came up or went down. We forward
    these to `Metadata` to trigger an immediate recomputation rather than
    waiting for the 60s scheduler.

  - `:cluster_scope` — registry where each Gateway registers itself.
    We do NOT forward these events to Metadata — gateway churn is a consequence
    of recomputation, not a cause of it.

  ## Delivery guarantees

  Syn calls these callbacks synchronously inside its own scope process, so we
  must not block. `send/2` is instantaneous — the actual work happens in the
  `Metadata` GenServer's mailbox.

  Syn wraps each callback in a `try/catch`, so a crash here will be logged but
  will not crash the syn scope process.

  ## Registration

  Registered globally via `config :syn, event_handler: EdgeAdmin.Admins.SynEventHandler`
  in `config.exs`. Syn loads this once at startup via `ensure_event_handler_loaded/0`.
  """

  @behaviour :syn_event_handler

  require Logger

  # Called on every node when a process joins a group.
  # We only act on :admin_scope — gateway registrations in :cluster_scope are ignored.
  @impl true
  def on_process_joined(:admin_scope, _group, _pid, metadata, reason) do
    admin_name = Map.get(metadata, :name, "unknown")
    Logger.info("SynEventHandler: admin joined — #{admin_name} (reason: #{inspect(reason)})")
    notify_metadata(:admin_join)
  end

  def on_process_joined(_scope, _group, _pid, _metadata, _reason), do: :ok

  # Called on every node when a process leaves a group (graceful or crash).
  # reason is :normal for graceful leave, or the crash reason (e.g. :noconnection) for failures.
  @impl true
  def on_process_left(:admin_scope, _group, _pid, metadata, reason) do
    admin_name = Map.get(metadata, :name, "unknown")
    Logger.info("SynEventHandler: admin left — #{admin_name} (reason: #{inspect(reason)})")
    notify_metadata(:admin_leave)
  end

  def on_process_left(_scope, _group, _pid, _metadata, _reason), do: :ok

  # Send a recomputation request to the local Metadata process.
  # Guards against the race where Metadata hasn't started yet (e.g. during bootstrap).
  defp notify_metadata(trigger) do
    case Process.whereis(EdgeAdmin.Admins.Metadata) do
      nil ->
        Logger.debug("SynEventHandler: Metadata not yet started, skipping #{trigger} notification")

      pid ->
        send(pid, {:syn_admin_topology_changed, trigger})
    end
  end
end
