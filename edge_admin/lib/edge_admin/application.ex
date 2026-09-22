# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  OTP application entry point and supervision tree.

  The supervision tree is selected by the configured supervision profile. The
  active repository implementation is selected at runtime, and optional
  integrations start only when enabled by configuration.
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
    admin_clustering_children() ++
      gateway_registry_children() ++
      admin_clustering_scheduler_children() ++
      proxy_children() ++
      endpoint_children()
  end

  # Shared infrastructure and Admin-cluster membership.
  defp admin_clustering_children do
    [EdgeAdmin.PromEx, EdgeAdmin.Encryption] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        EdgeAdminWeb.Telemetry,
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdmin.AdminClustering.Membership.Bootstrap
      ]
  end

  # The Gateway Registry supervises edge-cluster VPN memberships and virtual
  # Gateway lifecycles.
  defp gateway_registry_children do
    [
      EdgeAdmin.GatewayRegistry.Supervisor,
      EdgeAdmin.GatewayRegistry.Coordinator
    ]
  end

  # Metadata recomputation and periodic Admin-cluster work.
  defp admin_clustering_scheduler_children do
    [
      EdgeAdmin.AdminClustering.Metadata,
      EdgeAdmin.BackgroundJobs.Quantum.History,
      EdgeAdmin.BackgroundJobs.Quantum
    ]
  end

  # Proxy children include the raw Admin-to-Admin tunnel and edge-facing
  # proxy servers.
  defp proxy_children do
    [EdgeAdminProxy.Supervisor]
  end

  # Public Admin endpoints.
  defp endpoint_children do
    [
      EdgeAdmin.PromEx.Server,
      {EdgeAdminMcp.Server, transport: :streamable_http, registry: {Anubis.Server.Registry.PG, []}},
      EdgeAdminMcp.HttpServer,
      EdgeAdminWeb.Endpoint
    ] ++ event_broker_children()
  end
end
