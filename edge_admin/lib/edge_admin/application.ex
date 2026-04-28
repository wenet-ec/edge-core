# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application

  alias EdgeAdmin.Repo.Notifier

  @impl true
  def start(_type, _args) do
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
      [EdgeAdmin.EventBroker.Supervisor]
    else
      []
    end
  end

  defp runtime_mode do
    if System.get_env("EDGE_ADMIN_MODE") == "test", do: :test, else: :server
  end

  defp build_children(:test) do
    [
      EdgeAdmin.Repo,
      Notifier,
      {Phoenix.PubSub, name: EdgeAdmin.PubSub},
      {Oban, Application.fetch_env!(:edge_admin, Oban)},
      EdgeAdminWeb.Endpoint
    ]
  end

  defp build_children(:server) do
    [
      EdgeAdmin.PromEx,
      EdgeAdmin.Repo,
      Notifier,
      {Phoenix.PubSub, name: EdgeAdmin.PubSub},
      EdgeAdminWeb.Telemetry,
      EdgeAdminWeb.Live.NetmakerDashboard.Collector,
      {Oban, Application.fetch_env!(:edge_admin, Oban)},
      EdgeAdmin.Admins.Bootstrap,
      EdgeAdmin.EdgeClusters.Supervisor,
      EdgeAdmin.EdgeClusters,
      EdgeAdmin.Admins.Metadata,
      EdgeAdmin.LocalScheduler,
      EdgeAdmin.ProxyServers.Transport.TunnelRegistry,
      EdgeAdmin.ProxyServers,
      {EdgeAdminMcp.Server, transport: :streamable_http},
      EdgeAdminWeb.Endpoint
    ] ++ event_broker_children()
  end
end
