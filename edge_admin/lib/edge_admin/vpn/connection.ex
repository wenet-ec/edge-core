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

    timestamps(type: :utc_datetime)
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
      # Note: inserted_at and updated_at are automatically handled by timestamps()
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, [:connected, :disconnected, :connecting])
  end

  def new(attrs \\ %{}) do
    now = DateTime.utc_now()

    %__MODULE__{
      status: :disconnected,
      last_checked_at: now,
      manual_disconnect: false,
      inserted_at: now,
      updated_at: now
    }
    |> changeset(attrs)
    |> apply_action!(:validate)
  end
end
