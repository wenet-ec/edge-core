# edge_agent/lib/edge_agent_metrics/supervisor.ex
defmodule EdgeAgentMetrics.Supervisor do
  @moduledoc """
  Supervises the Agent metrics subsystem.

  The exporter manager has its own lifecycle boundary so metrics failures do
  not affect the Agent SSH, proxy, VPN, or bootstrap services.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([EdgeAgentMetrics], strategy: :one_for_one)
  end
end
