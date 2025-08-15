# tailscale/lib/tailscale/connection.ex
defmodule Tailscale.Connection do
  @moduledoc """
  Struct representing Tailscale VPN connection state.

  This struct represents the current state of the Tailscale VPN connection,
  including status, connection details, error information, and configuration.
  """

  @type status :: :connected | :disconnected | :connecting

  @type t :: %__MODULE__{
          status: status(),
          vpn_ip: String.t() | nil,
          vpn_hostname: String.t() | nil,
          connected_at: DateTime.t() | nil,
          last_checked_at: DateTime.t() | nil,
          last_error: String.t() | nil,
          last_error_at: DateTime.t() | nil,
          manual_disconnect: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :status,
    :vpn_ip,
    :vpn_hostname,
    :connected_at,
    :last_checked_at,
    :last_error,
    :last_error_at,
    :manual_disconnect,
    :inserted_at,
    :updated_at
  ]

  @doc """
  Creates a new connection with default values.
  """
  def new(attrs \\ %{}) do
    now = DateTime.utc_now()

    default_attrs = %{
      status: :disconnected,
      last_checked_at: now,
      manual_disconnect: false,
      inserted_at: now,
      updated_at: now
    }

    merged_attrs = Map.merge(default_attrs, attrs)
    struct(__MODULE__, merged_attrs)
  end

  @doc """
  Updates a connection with new attributes.
  """
  def update(%__MODULE__{} = connection, attrs) do
    attrs_with_timestamp = Map.put(attrs, :updated_at, DateTime.utc_now())
    
    updated_connection = 
      connection
      |> Map.merge(attrs_with_timestamp)
      |> validate()

    case updated_connection do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates connection fields.
  """
  def validate(%__MODULE__{} = connection) do
    with :ok <- validate_status(connection.status),
         :ok <- validate_manual_disconnect(connection.manual_disconnect) do
      {:ok, connection}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(invalid) do
    {:error, "Invalid connection struct: #{inspect(invalid)}"}
  end

  # Private validation functions

  defp validate_status(status) when status in [:connected, :disconnected, :connecting], do: :ok
  defp validate_status(invalid), do: {:error, "Invalid status: #{inspect(invalid)}"}

  defp validate_manual_disconnect(value) when is_boolean(value), do: :ok
  defp validate_manual_disconnect(invalid), do: {:error, "manual_disconnect must be boolean, got: #{inspect(invalid)}"}
end