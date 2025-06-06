# edge_agent/lib/edge_agent/application.ex
defmodule EdgeAgent.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EdgeAgent.Repo,
      {DNSCluster, query: Application.get_env(:edge_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EdgeAgent.PubSub},
      # Add Oban to the supervision tree
      {Oban, Application.fetch_env!(:edge_agent, Oban)},
      # Start to serve requests, typically the last entry
      EdgeAgentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EdgeAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdgeAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
