# edge_agent/lib/edge_agent/application.ex
defmodule EdgeAgent.Application do
  @moduledoc """
  Application entry point and supervision tree builder for the Edge Agent.

  The `:supervision_profile` setting selects the minimal test tree or the full
  server tree. Both profiles validate the Oban queue manifest before startup.
  Children use `:one_for_one`, so a failed subsystem is restarted independently
  of its siblings.
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
