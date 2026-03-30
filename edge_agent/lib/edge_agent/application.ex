# edge_agent/lib/edge_agent/application.ex
defmodule EdgeAgent.Application do
  @moduledoc """
  Main entry point of the app
  """

  use Application

  alias EdgeAgent.Commands.ExecutionRegistry

  require Logger

  @impl true
  def start(_type, _args) do
    mode = runtime_mode()
    children = build_children(mode)

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

  defp runtime_mode do
    case System.get_env("EDGE_AGENT_MODE") do
      "test" -> :test
      _ -> :server
    end
  end

  defp build_children(:test) do
    [
      EdgeAgent.Repo,
      {Phoenix.PubSub, name: EdgeAgent.PubSub},
      {Oban, Application.fetch_env!(:edge_agent, Oban)},
      ExecutionRegistry,
      EdgeAgentWeb.Endpoint
    ]
  end

  defp build_children(:server) do
    [
      EdgeAgent.Repo,
      {Phoenix.PubSub, name: EdgeAgent.PubSub},
      {Oban, Application.fetch_env!(:edge_agent, Oban)},
      EdgeAgent.PromEx,
      ExecutionRegistry,
      EdgeAgent.SshServer,
      EdgeAgent.MetricsServers,
      EdgeAgent.ProxyServers,
      EdgeAgent.Bootstrap,
      EdgeAgent.Vpn.DerpMapCache,
      EdgeAgent.Lan.Mdns,
      EdgeAgentWeb.Endpoint
    ]
  end
end
