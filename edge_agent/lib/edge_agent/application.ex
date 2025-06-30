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
      EdgeAgent.Tailscale.ConnectionManager,
      {Oban, Application.fetch_env!(:edge_agent, Oban)},
      EdgeAgent.SshServer,
      EdgeAgent.MetricsServer.Server,
      EdgeAgentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EdgeAgent.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Only run bootstrap if not in test environment
        if should_run_bootstrap?() do
          case EdgeAgent.Bootstrap.run() do
            {:ok, :bootstrap_complete} ->
              {:ok, pid}

            {:error, reason} ->
              Logger.error("Bootstrap failed: #{inspect(reason)}")
              # Continue for now, but you might want {:error, reason}
              {:ok, pid}
          end
        else
          Logger.info("Skipping bootstrap in #{Mix.env()} environment")
          {:ok, pid}
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

  # Private function to determine if bootstrap should run
  defp should_run_bootstrap? do
    # Skip bootstrap in test environment
    # You can also add other conditions like checking for specific environment variables
    case Application.get_env(:edge_agent, :run_bootstrap, :auto) do
      false -> false
      true -> true
      :auto -> Mix.env() != :test
    end
  end
end
