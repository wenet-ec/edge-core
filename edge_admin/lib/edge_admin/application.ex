# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  OTP application entry point and supervision tree.

  Two child-tree shapes selected by `EDGE_ADMIN_MODE`:

    * `EDGE_ADMIN_MODE=test` — minimal tree (Vault, Repo, PubSub, Oban,
      Endpoint). Used by the test env; skips PromEx, Membership, GatewayRegistry,
      Metadata, LocalScheduler, EdgeAdminProxy, MCP, etc.
  * unset (default) — full server tree.

  The full server tree is the default bundled Admin role. It currently runs
  both architectural responsibilities in one application: the Admin Router
  and the Gateway Registry. A future `ADMIN_ROLE` configuration may select
  `default` (both responsibilities), `router`, or `gateway_registry`; that
  role split is not active yet, so the current server tree always starts both.

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
    [EdgeAdmin.Encryption] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdminWeb.Endpoint
      ]
  end

  defp build_children(:server) do
    router_foundation_children() ++
      gateway_registry_children() ++
      router_scheduler_children() ++
      gateway_proxy_children() ++
      router_endpoint_children()
  end

  # Router-owned children coordinate the Core and expose the public control
  # plane.
  defp router_foundation_children do
    [EdgeAdmin.PromEx, EdgeAdmin.Encryption] ++
      repo_children() ++
      [
        {Phoenix.PubSub, name: EdgeAdmin.PubSub},
        EdgeAdminWeb.Telemetry,
        {Oban, Application.fetch_env!(:edge_admin, Oban)},
        EdgeAdmin.AdminClustering.Membership
      ]
  end

  # Gateway Registry children manage edge-cluster VPN memberships and virtual
  # Gateway lifecycles.
  defp gateway_registry_children do
    [
      EdgeAdmin.GatewayRegistry.Supervisor,
      EdgeAdmin.GatewayRegistry.Coordinator
    ]
  end

  defp router_scheduler_children do
    [EdgeAdmin.AdminClustering.Metadata, EdgeAdmin.LocalScheduler.History, EdgeAdmin.LocalScheduler]
  end

  # Data-plane proxy children include the raw Admin-to-Admin tunnel and the
  # edge-facing proxy servers.
  defp gateway_proxy_children do
    [EdgeAdminProxy.Supervisor]
  end

  defp router_endpoint_children do
    [
      EdgeAdmin.PromEx.Server,
      {EdgeAdminMcp.Server, transport: :streamable_http, registry: {Anubis.Server.Registry.PG, []}},
      EdgeAdminWeb.Endpoint
    ] ++ event_broker_children()
  end
end
