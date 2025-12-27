# edge_agent/lib/edge_agent/commands/execution_registry.ex
defmodule EdgeAgent.Commands.ExecutionRegistry do
  @moduledoc """
  Registry for tracking currently executing command tasks.

  Stores task PIDs for running commands to enable cancellation.
  Used by cancel_execution to kill actively running commands.
  """

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Registers a task PID for a command execution.
  """
  def register(execution_id, task_pid) do
    GenServer.cast(__MODULE__, {:register, execution_id, task_pid})
  end

  @doc """
  Unregisters a task PID for a command execution.
  """
  def unregister(execution_id) do
    GenServer.cast(__MODULE__, {:unregister, execution_id})
  end

  @doc """
  Gets the task PID for a command execution.
  Returns nil if not found.
  """
  def get_task(execution_id) do
    GenServer.call(__MODULE__, {:get_task, execution_id})
  end

  # GenServer callbacks

  def init(_), do: {:ok, %{}}

  def handle_cast({:register, execution_id, task_pid}, state) do
    {:noreply, Map.put(state, execution_id, task_pid)}
  end

  def handle_cast({:unregister, execution_id}, state) do
    {:noreply, Map.delete(state, execution_id)}
  end

  def handle_call({:get_task, execution_id}, _from, state) do
    {:reply, Map.get(state, execution_id), state}
  end
end
