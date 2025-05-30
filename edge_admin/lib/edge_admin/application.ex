# lib/edge_admin/application.ex
defmodule EdgeAdmin.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EdgeAdmin.Repo,
      {DNSCluster, query: Application.get_env(:edge_admin, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EdgeAdmin.PubSub},
      # Add Oban to the supervision tree
      {Oban, Application.fetch_env!(:edge_admin, Oban)},
      # Start to serve requests, typically the last entry
      EdgeAdminWeb.Endpoint,
      {TelemetryUI, EdgeAdmin.TelemetryUI.config()}
    ]

    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{
        metadata: [:file, :line]
      }
    })

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
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
end
