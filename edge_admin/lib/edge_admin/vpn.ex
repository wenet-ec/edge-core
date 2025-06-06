# edge_admin/lib/edge_admin/vpn.ex
defmodule EdgeAdmin.VPN do
  @moduledoc """
  The VPN context manages the EdgeAdmin service's VPN connection state.

  Follows standard CRUD patterns with in-memory storage via GenServer + ETS.
  """

  alias EdgeAdmin.VPN.ConnectionManager

  # Standard CRUD operations

  @doc """
  Gets the current VPN connection record.
  """
  def get_connection do
    ConnectionManager.get_connection()
  end

  @doc """
  Creates a new VPN connection record.
  Only used for initialization - there's always exactly one record.
  """
  def create_connection(attrs \\ %{}) do
    ConnectionManager.create_connection(attrs)
  end

  @doc """
  Updates the VPN connection record.
  """
  def update_connection(attrs) do
    ConnectionManager.update_connection(attrs)
  end

  @doc """
  Gets the connection, raising if not found.
  """
  def get_connection! do
    case get_connection() do
      {:ok, connection} -> connection
      {:error, _} -> raise "VPN connection not found"
    end
  end
end
