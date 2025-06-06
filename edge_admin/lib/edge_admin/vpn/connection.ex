# edge_admin/lib/edge_admin/vpn/connection.ex
defmodule EdgeAdmin.VPN.Connection do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

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
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :status,
      :vpn_ip,
      :vpn_hostname,
      :connected_at,
      :last_checked_at,
      :last_error,
      :last_error_at,
      :manual_disconnect
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:connected, :disconnected, :connecting])
  end

  def new(attrs \\ %{}) do
    %__MODULE__{
      status: :disconnected,
      last_checked_at: DateTime.utc_now(),
      manual_disconnect: false
    }
    |> changeset(attrs)
    |> apply_action!(:validate)
  end
end
