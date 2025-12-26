# edge_admin/lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    mode = runtime_mode()
    children = build_children(mode)

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
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

  defp runtime_mode do
    case System.get_env("EDGE_ADMIN_MODE") do
      "task" -> :task
      _ -> :server
    end
  end

  defp build_children(:task) do
    [
      EdgeAdmin.PromEx,
      EdgeAdmin.Repo,
      {Phoenix.PubSub, name: EdgeAdmin.PubSub},
      {Oban, Application.fetch_env!(:edge_admin, Oban)}
    ]
  end

  defp build_children(:server) do
    [
      EdgeAdmin.PromEx,
      EdgeAdmin.Repo,
      {Phoenix.PubSub, name: EdgeAdmin.PubSub},
      EdgeAdminWeb.Telemetry,
      EdgeAdminWeb.NetmakerDashboard.Collector,
      {Oban, Application.fetch_env!(:edge_admin, Oban)},
      EdgeAdmin.Admins.Bootstrap,
      EdgeAdmin.EdgeClusters.Supervisor,
      EdgeAdmin.EdgeClusters,
      EdgeAdmin.Admins.Metadata,
      EdgeAdmin.LocalScheduler,
      EdgeAdmin.ProxyServer,
      EdgeAdminWeb.Endpoint
    ]
  end
end
