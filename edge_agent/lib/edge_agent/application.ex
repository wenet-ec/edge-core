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
      EdgeAgentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EdgeAgent.Supervisor]
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Run bootstrap after supervisor starts successfully
        case EdgeAgent.Bootstrap.run() do
          {:ok, :bootstrap_complete} ->
            {:ok, pid}
          {:error, reason} ->
            # Bootstrap failed - you can decide whether to:
            # 1. Continue anyway (for development)
            # 2. Crash the application (for production)
            Logger.error("Bootstrap failed: #{inspect(reason)}")
            {:ok, pid}  # Continue for now, but you might want {:error, reason}
        end

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdgeAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
