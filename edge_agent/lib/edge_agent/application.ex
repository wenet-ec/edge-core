# edge_agent/lib/edge_agent/application.ex
defmodule EdgeAgent.Application do
  @moduledoc """
  Application entry point and supervision tree builder for the edge agent.

  ## Supervision profiles

  The supervision tree is selected by the `:supervision_profile` application
  setting:

  - `:test` — minimal tree: `Repo`, `PubSub`, `Oban`, `ExecutionRegistry`,
    `Endpoint`. No `Bootstrap`, `EdgeAgentSsh`, `EdgeAgentMetrics`, `EdgeAgentProxy`,
    `PromEx`, `DerpMapCache`, or `Mdns` — keeps tests free of external
    side effects (VPN join, port binds, OpenSSL host-key generation).
  - `:server` (default) — full server tree.

  Strategy is `:one_for_one`: each child supervises independently, so a
  Bootstrap failure restarts only Bootstrap (eventually crashing the
  application supervisor if it exhausts restart intensity — see
  `EdgeAgent.Bootstrap` moduledoc for details).
  """

  use Application

  alias EdgeAgent.Commands.ExecutionRegistry

  @impl true
  def start(_type, _args) do
    # Crash early on Oban queue/worker drift — silent-failure class.
    EdgeAgent.BackgroundJobs.Oban.Queues.assert_consistent!()

    profile = Application.fetch_env!(:edge_agent, :supervision_profile)
    children = build_children(profile)

    opts = [strategy: :one_for_one, name: EdgeAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    EdgeAgentWeb.Endpoint.config_change(changed, removed)
    :ok
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
      EdgeAgent.BackgroundJobs.Quantum,
      EdgeAgent.PromEx,
      ExecutionRegistry,
      EdgeAgentSsh.Supervisor,
      EdgeAgentMetrics.Supervisor,
      EdgeAgentProxy.Supervisor,
      EdgeAgent.Bootstrap,
      EdgeAgent.Vpn.DerpMapCache,
      EdgeAgent.Lan.Mdns,
      EdgeAgent.PromEx.Server,
      EdgeAgentWeb.Endpoint
    ]
  end
end
