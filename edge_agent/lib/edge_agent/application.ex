# edge_agent/lib/edge_agent/application.ex
defmodule EdgeAgent.Application do
  @moduledoc """
  Application entry point and supervision tree builder for the edge agent.

  ## Runtime modes

  The supervision tree is selected by `EDGE_AGENT_MODE`:

  - `"test"` — minimal tree: `Repo`, `PubSub`, `Oban`, `ExecutionRegistry`,
    `Endpoint`. No `Bootstrap`, `SshServer`, `MetricsServers`, `ProxyServers`,
    `PromEx`, `DerpMapCache`, or `Mdns` — keeps tests free of external
    side effects (VPN join, port binds, OpenSSL host-key generation).
  - any other value (incl. unset) — full `:server` tree.

  Strategy is `:one_for_one`: each child supervises independently, so a
  Bootstrap failure restarts only Bootstrap (eventually crashing the
  application supervisor if it exhausts restart intensity — see
  `EdgeAgent.Bootstrap` moduledoc for details).
  """

  use Application

  alias EdgeAgent.Commands.ExecutionRegistry

  require Logger

  @impl true
  def start(_type, _args) do
    # Crash early on Oban queue/worker drift — silent-failure class.
    EdgeAgent.Oban.Queues.assert_consistent!()

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
      EdgeAgent.ProxyServers.Transport.TunnelRegistry,
      EdgeAgent.ProxyServers,
      EdgeAgent.Bootstrap,
      EdgeAgent.Vpn.DerpMapCache,
      EdgeAgent.Lan.Mdns,
      EdgeAgentWeb.Endpoint
    ]
  end
end
