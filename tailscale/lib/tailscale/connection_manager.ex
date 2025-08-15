# tailscale/lib/tailscale/connection_manager.ex
defmodule Tailscale.ConnectionManager do
  @moduledoc """
  Manages Tailscale connection state in memory.

  This module provides functions to create, retrieve, and update
  the Tailscale connection state. It uses a GenServer to maintain
  state in memory, making it suitable for applications that don't
  need persistent storage or want to manage persistence themselves.
  """

  use GenServer

  alias Tailscale.Connection

  require Logger

  @connection_key :tailscale_connection

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current connection state.
  """
  def get_connection do
    GenServer.call(__MODULE__, :get_connection)
  end

  @doc """
  Creates a new connection with the given attributes.
  """
  def create_connection(attrs \\ %{}) do
    GenServer.call(__MODULE__, {:create_connection, attrs})
  end

  @doc """
  Updates the current connection with new attributes.
  """
  def update_connection(connection, attrs) do
    GenServer.call(__MODULE__, {:update_connection, connection, attrs})
  end

  @doc """
  Resets the connection state (useful for testing).
  """
  def reset_connection do
    GenServer.call(__MODULE__, :reset_connection)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize with a default disconnected connection
    connection = Connection.new()
    state = %{@connection_key => connection}
    
    Logger.debug("Tailscale.ConnectionManager initialized")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_connection, _from, state) do
    connection = Map.get(state, @connection_key)
    
    case connection do
      %Connection{} = conn ->
        {:reply, {:ok, conn}, state}
      nil ->
        # Create default connection if none exists
        default_connection = Connection.new()
        new_state = Map.put(state, @connection_key, default_connection)
        {:reply, {:ok, default_connection}, new_state}
    end
  end

  @impl true
  def handle_call({:create_connection, attrs}, _from, state) do
    case Connection.new(attrs) do
      %Connection{} = connection ->
        new_state = Map.put(state, @connection_key, connection)
        Logger.debug("Created new Tailscale connection with status: #{connection.status}")
        {:reply, {:ok, connection}, new_state}
      
      error ->
        Logger.error("Failed to create Tailscale connection: #{inspect(error)}")
        {:reply, {:error, "Failed to create connection"}, state}
    end
  end

  @impl true
  def handle_call({:update_connection, _current_connection, attrs}, _from, state) do
    current_connection = Map.get(state, @connection_key)
    
    case current_connection do
      %Connection{} = conn ->
        case Connection.update(conn, attrs) do
          {:ok, updated_connection} ->
            new_state = Map.put(state, @connection_key, updated_connection)
            Logger.debug("Updated Tailscale connection status: #{updated_connection.status}")
            {:reply, {:ok, updated_connection}, new_state}
          
          {:error, reason} ->
            Logger.error("Failed to update Tailscale connection: #{reason}")
            {:reply, {:error, reason}, state}
        end
      
      nil ->
        # If no connection exists, create a new one with the attrs
        case Connection.new(attrs) do
          %Connection{} = connection ->
            new_state = Map.put(state, @connection_key, connection)
            Logger.debug("Created new Tailscale connection during update with status: #{connection.status}")
            {:reply, {:ok, connection}, new_state}
          
          error ->
            Logger.error("Failed to create Tailscale connection during update: #{inspect(error)}")
            {:reply, {:error, "Failed to create connection"}, state}
        end
    end
  end

  @impl true
  def handle_call(:reset_connection, _from, _state) do
    connection = Connection.new()
    new_state = %{@connection_key => connection}
    Logger.debug("Reset Tailscale connection state")
    {:reply, {:ok, connection}, new_state}
  end

  # Optional: Child spec for supervision tree
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end