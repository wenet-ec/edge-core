# edge_agent/lib/edge_agent/proxy_servers/transport/tunnel_registry.ex
defmodule EdgeAgent.ProxyServers.Transport.TunnelRegistry do
  @moduledoc """
  Tracks live proxy handler processes so they can be signalled for graceful
  drain on shutdown.

  Backed by an ETS table owned by a supervised GenServer. Handlers call
  `register/1` on entry and `unregister/1` on exit; the registry demonitors
  them automatically if the owner crashes.

  `drain/1` sends every registered handler a `{:drain, grace_ms}` message and
  returns — the caller then waits for the handlers to exit.
  """

  use GenServer

  require Logger

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register(map()) :: :ok
  def register(metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, self(), metadata})
  end

  @spec unregister() :: :ok
  def unregister do
    GenServer.cast(__MODULE__, {:unregister, self()})
  end

  @spec handlers() :: [pid()]
  def handlers do
    case :ets.whereis(@table) do
      :undefined -> []
      _ -> @table |> :ets.tab2list() |> Enum.map(fn {pid, _ref, _meta} -> pid end)
    end
  end

  @spec count() :: non_neg_integer()
  def count do
    case :ets.whereis(@table) do
      :undefined -> 0
      _ -> :ets.info(@table, :size) || 0
    end
  end

  @spec drain(non_neg_integer()) :: non_neg_integer()
  def drain(grace_ms) do
    pids = handlers()
    Enum.each(pids, fn pid -> send(pid, {:drain, grace_ms}) end)
    length(pids)
  end

  @spec wait_for_empty(non_neg_integer()) :: :ok | {:timeout, non_neg_integer()}
  def wait_for_empty(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_for_empty(deadline)
  end

  defp poll_for_empty(deadline) do
    case count() do
      0 ->
        :ok

      n ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:timeout, n}
        else
          Process.sleep(50)
          poll_for_empty(deadline)
        end
    end
  end

  @spec force_close() :: non_neg_integer()
  def force_close do
    pids = handlers()
    Enum.each(pids, fn pid -> Process.exit(pid, :drain_timeout) end)
    length(pids)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table, monitors: %{}}}
  end

  @impl true
  def handle_call({:register, pid, metadata}, _from, state) do
    ref = Process.monitor(pid)
    :ets.insert(@table, {pid, ref, metadata})
    {:reply, :ok, %{state | monitors: Map.put(state.monitors, ref, pid)}}
  end

  @impl true
  def handle_cast({:unregister, pid}, state) do
    new_monitors =
      case :ets.lookup(@table, pid) do
        [{^pid, ref, _meta}] ->
          Process.demonitor(ref, [:flush])
          :ets.delete(@table, pid)
          Map.delete(state.monitors, ref)

        [] ->
          state.monitors
      end

    {:noreply, %{state | monitors: new_monitors}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    :ets.delete(@table, pid)
    {:noreply, %{state | monitors: Map.delete(state.monitors, ref)}}
  end
end
