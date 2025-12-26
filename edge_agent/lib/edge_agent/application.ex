# edge_agent/lib/edge_agent/application.ex
defmodule EdgeAgent.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      EdgeAgent.Repo,
      {DNSCluster, query: Application.get_env(:edge_agent, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EdgeAgent.PubSub},
      {Oban, Application.fetch_env!(:edge_agent, Oban)},
      EdgeAgent.PromEx,
      EdgeAgent.SshServer,
      EdgeAgent.MetricsServers,
      EdgeAgent.ProxyServers,
      EdgeAgent.Bootstrap,
      EdgeAgentWeb.Endpoint
    ]

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
