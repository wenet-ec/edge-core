# edge_agent/lib/edge_agent_ssh/supervisor.ex
defmodule EdgeAgentSsh.Supervisor do
  @moduledoc """
  Supervises the Agent SSH subsystem.

  The SSH daemon has its own lifecycle boundary so failures in SSH do not
  affect the Agent proxy, metrics exporters, VPN, or bootstrap services.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([EdgeAgentSsh], strategy: :one_for_one)
  end
end
