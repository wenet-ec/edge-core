# edge_admin/lib/edge_admin/vpn/connection.ex
defmodule EdgeAdmin.VPN.Connection do
  @moduledoc """
  Embedded Ecto schema for VPN connection data in EdgeAdmin.
  
  This schema provides EdgeAdmin-specific validation and changeset functionality
  while proxying the shared Tailscale.Connection struct. It leverages Phoenix/Ecto
  ecosystem benefits without database mapping.
  """

  use Ecto.Schema
  import Ecto.Changeset

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

  @primary_key false
  embedded_schema do
    field(:status, Ecto.Enum, values: [:connected, :disconnected, :connecting])
    field(:vpn_ip, :string)
    field(:vpn_hostname, :string)
    field(:connected_at, :utc_datetime)
    field(:last_checked_at, :utc_datetime)
    field(:last_error, :string)
    field(:last_error_at, :utc_datetime)
    field(:manual_disconnect, :boolean, default: false)
    field(:inserted_at, :utc_datetime)
    field(:updated_at, :utc_datetime)
  end

  @doc """
  Creates a new Connection from a Tailscale.Connection struct.
  """
  def from_tailscale_connection(%Tailscale.Connection{} = tailscale_conn) do
    %__MODULE__{
      status: tailscale_conn.status,
      vpn_ip: tailscale_conn.vpn_ip,
      vpn_hostname: tailscale_conn.vpn_hostname,
      connected_at: tailscale_conn.connected_at,
      last_checked_at: tailscale_conn.last_checked_at,
      last_error: tailscale_conn.last_error,
      last_error_at: tailscale_conn.last_error_at,
      manual_disconnect: tailscale_conn.manual_disconnect,
      inserted_at: tailscale_conn.inserted_at,
      updated_at: tailscale_conn.updated_at
    }
  end

  @doc """
  Converts this embedded schema back to a Tailscale.Connection struct.
  """
  def to_tailscale_connection(%__MODULE__{} = connection) do
    %Tailscale.Connection{
      status: connection.status,
      vpn_ip: connection.vpn_ip,
      vpn_hostname: connection.vpn_hostname,
      connected_at: connection.connected_at,
      last_checked_at: connection.last_checked_at,
      last_error: connection.last_error,
      last_error_at: connection.last_error_at,
      manual_disconnect: connection.manual_disconnect,
      inserted_at: connection.inserted_at,
      updated_at: connection.updated_at
    }
  end

  @doc """
  Changeset for updating connection properties.
  """
  def update_changeset(%__MODULE__{} = connection, attrs) do
    connection
    |> cast(attrs, [:manual_disconnect])
    |> validate_required([:manual_disconnect])
    |> validate_inclusion(:manual_disconnect, [true, false])
  end

  @doc """
  Changeset for creating/transforming from Tailscale.Connection.
  """
  def changeset(%__MODULE__{} = connection, attrs) do
    connection
    |> cast(attrs, [
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
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:connected, :disconnected, :connecting])
    |> validate_inclusion(:manual_disconnect, [true, false])
    |> validate_ip_address(:vpn_ip)
  end

  defp validate_ip_address(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case value do
        nil -> []
        "" -> []
        ip when is_binary(ip) ->
          case :inet.parse_address(String.to_charlist(ip)) do
            {:ok, _} -> []
            {:error, _} -> [{field, "must be a valid IP address"}]
          end
        _ -> [{field, "must be a string"}]
      end
    end)
  end
end