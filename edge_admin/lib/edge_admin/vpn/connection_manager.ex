# edge_admin/lib/edge_admin/vpn/connection_manager.ex
defmodule EdgeAdmin.VPN.ConnectionManager do
  @moduledoc false
  use GenServer

  alias EdgeAdmin.VPN.Connection

  require Logger

  @table_name :vpn_connection

  # Client API - Pure CRUD

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_connection do
    GenServer.call(__MODULE__, :get)
  end

  def create_connection(attrs) do
    GenServer.call(__MODULE__, {:create, attrs})
  end

  def update_connection(attrs) do
    GenServer.call(__MODULE__, {:update, attrs})
  end

  # Server callbacks

  @impl true
  def init(_) do
    :ets.new(@table_name, [:set, :named_table, :public])

    # Create initial connection record
    initial_connection = Connection.new()
    store_connection(initial_connection)

    Logger.info("VPN Connection Manager initialized with CRUD interface")
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    case load_connection() do
      nil -> {:reply, {:error, :not_found}, state}
      connection -> {:reply, {:ok, connection}, state}
    end
  end

  @impl true
  def handle_call({:create, attrs}, _from, state) do
    # Only create if doesn't exist (singleton pattern)
    case load_connection() do
      nil ->
        connection = Connection.new(attrs)
        store_connection(connection)
        {:reply, {:ok, connection}, state}

      existing ->
        {:reply, {:ok, existing}, state}
    end
  end

  @impl true
  def handle_call({:update, attrs}, _from, state) do
    case load_connection() do
      nil ->
        # Create if doesn't exist
        connection = Connection.new(attrs)
        store_connection(connection)
        {:reply, {:ok, connection}, state}

      current ->
        current_map = Map.from_struct(current)
        updated_attrs = Map.merge(attrs, %{updated_at: DateTime.utc_now()})
        updated_attrs = Map.merge(current_map, updated_attrs)
        updated_connection = Connection.new(updated_attrs)
        store_connection(updated_connection)
        {:reply, {:ok, updated_connection}, state}
    end
  end

  # Private functions

  defp store_connection(connection) do
    :ets.insert(@table_name, {:singleton, connection})
  end

  defp load_connection do
    case :ets.lookup(@table_name, :singleton) do
      [{:singleton, connection}] -> connection
      [] -> nil
    end
  end
end
