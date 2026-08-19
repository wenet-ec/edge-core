# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  OTP application entry point and supervision tree.

  Two child-tree shapes selected by the `:supervision_profile` application
  setting:

    * `:test` — minimal tree (Vault, Repo, PubSub, Oban,
      Endpoint). Used by the test env; skips PromEx, AdminClustering,
      GatewayRegistry, Metadata, Quantum, EdgeAdminProxy, MCP, etc.
    * `:server` (default) — the bundled Admin tree.

  The bundled Admin contains both conceptual responsibilities in one
  application: Admin Clustering coordinates membership, metadata, ownership,
  and reconciliation; the Gateway Registry supervises the local virtual
  gateway workers and their data-plane access. Router and Worker are
  architectural descriptions of these responsibilities, not runtime modes.

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
    EdgeAdmin.BackgroundJobs.Oban.Queues.assert_consistent!()

    profile = Application.fetch_env!(:edge_admin, :supervision_profile)
    children = build_children(profile)

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

  defp event_broker_children do
    if Application.get_env(:edge_admin, :event_broker_enabled, false) do
      [EdgeAdmin.Events.Broker.Supervisor]
    else
      []
    end
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
    [EdgeAdmin.Encryption] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdminWeb.Endpoint
      ]
  end

  defp build_children(:server) do
    coordinator_foundation_children() ++
      worker_runtime_children() ++
      coordinator_scheduler_children() ++
      data_plane_proxy_children() ++
      public_endpoint_children()
  end

  # Coordinator foundation: shared infrastructure and Admin-cluster
  # membership used by the bundled Admin.
  defp coordinator_foundation_children do
    [EdgeAdmin.PromEx, EdgeAdmin.Encryption] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        EdgeAdminWeb.Telemetry,
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdmin.AdminClustering.Membership
      ]
  end

  # Worker runtime: the Gateway Registry supervises edge-cluster VPN
  # memberships and virtual Gateway lifecycles inside this same application.
  defp worker_runtime_children do
    [
      EdgeAdmin.GatewayRegistry.Supervisor,
      EdgeAdmin.GatewayRegistry.Coordinator
    ]
  end

  # Coordinator scheduling and metadata recomputation.
  defp coordinator_scheduler_children do
    [
      EdgeAdmin.AdminClustering.Metadata,
      EdgeAdmin.BackgroundJobs.Quantum.History,
      EdgeAdmin.BackgroundJobs.Quantum
    ]
  end

  # Data-plane proxy children include the raw Admin-to-Admin tunnel and the
  # edge-facing proxy servers.
  defp data_plane_proxy_children do
    [EdgeAdminProxy.Supervisor]
  end

  # Public control-plane endpoints. These remain in the bundled Admin and are
  # not a declaration of a separate deployment.
  defp public_endpoint_children do
    [
      EdgeAdmin.PromEx.Server,
      {EdgeAdminMcp.Server, transport: :streamable_http, registry: {Anubis.Server.Registry.PG, []}},
      EdgeAdminMcp.HttpServer,
      EdgeAdminWeb.Endpoint
    ] ++ event_broker_children()
  end
end
