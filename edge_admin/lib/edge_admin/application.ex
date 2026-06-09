# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  OTP application entry point and supervision tree.

  Two child-tree shapes selected by `EDGE_ADMIN_MODE`:

    * `EDGE_ADMIN_MODE=test` — minimal tree (Vault, Repo, PubSub, Oban,
      Endpoint). Used by the test env; skips PromEx, Membership, EdgeClusters,
      Metadata, LocalScheduler, ProxyServers, MCP, etc.
    * unset (default) — full server tree.

  The active repo is selected by `DB_ADAPTER` via `:repo_impl` (Postgres or
  SQLite). Postgres mode also starts a Notifier sub-repo for Oban LISTEN.

  Event-broker children only start when `EVENT_BROKER_ENABLED=true`.
  """

  use Application

  alias EdgeAdmin.Repo.Postgres
  alias EdgeAdmin.Repo.Postgres.Notifier

  @impl true
  def start(_type, _args) do
    # Crash early on Oban queue/worker drift — silent-failure class.
    EdgeAdmin.Oban.Queues.assert_consistent!()

    children = build_children(runtime_mode())

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line, :request_id, :mfa, :domain]}
    })

    opts = [strategy: :one_for_one, name: EdgeAdmin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdgeAdminWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp event_broker_children do
    if Application.get_env(:edge_admin, :event_broker_enabled, false) do
      [EdgeAdmin.Events.Broker.Supervisor]
    else
      []
    end
  end

  defp runtime_mode do
    if System.get_env("EDGE_ADMIN_MODE") == "test", do: :test, else: :server
  end

  # Start the active repo impl (selected at runtime via DB_ADAPTER → :repo_impl).
  # Postgres impl also starts a Notifier sub-repo for Oban LISTEN.
  defp repo_children do
    case Application.fetch_env!(:edge_admin, :repo_impl) do
      Postgres ->
        [Postgres, Notifier]

      impl ->
        [impl]
    end
  end

  defp build_children(:test) do
    [EdgeAdmin.Vault] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdminWeb.Endpoint
      ]
  end

  defp build_children(:server) do
    [EdgeAdmin.PromEx, EdgeAdmin.Vault] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        EdgeAdminWeb.Telemetry,
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdmin.Admins.Membership,
        EdgeAdmin.EdgeClusters.Supervisor,
        EdgeAdmin.EdgeClusters,
        EdgeAdmin.Admins.Metadata,
        EdgeAdmin.LocalScheduler.History,
        EdgeAdmin.LocalScheduler,
        EdgeAdmin.ProxyServers.Transport.TunnelRegistry,
        EdgeAdmin.ProxyServers,
        {EdgeAdminMcp.Server, transport: :streamable_http, registry: {Anubis.Server.Registry.PG, []}},
        EdgeAdminWeb.Endpoint
      ] ++ event_broker_children()
  end
end
