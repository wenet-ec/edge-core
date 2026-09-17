# edge_admin/lib/edge_admin/ingress_tunneling/schemas/tunnel_client.ex
defmodule EdgeAdmin.IngressTunneling.Schemas.TunnelClient do
  @moduledoc """
  Long-lived external Edge Tunnel WireGuard identity.

  Admin generates and stores this keypair. The public key identifies the
  Tunnel client to every selected Ingress; the private key is encrypted at
  rest and is delivered only in a generated Tunnel Connection artifact.
  """
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Encryption.EncryptedBinary
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.IngressTunneling.Validators.WireGuardKeyValidators

  @flop_options [
    filterable: [:inserted_at, :updated_at],
    sortable: [:inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          public_key: String.t(),
          private_key: binary(),
          tunnel_connections: [TunnelConnection.t()] | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "tunnel_clients" do
    field(:public_key, :string)
    field(:private_key, EncryptedBinary, redact: true)

    has_many(:tunnel_connections, TunnelConnection)

    timestamps()
  end

  @doc false
  def changeset(tunnel_client, attrs) do
    tunnel_client
    |> cast(attrs, [:public_key, :private_key])
    |> validate_required([:public_key, :private_key])
    |> validate_wireguard_key(:public_key)
    |> validate_wireguard_key(:private_key)
    |> unique_constraint(:public_key)
  end

  defp validate_wireguard_key(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if WireGuardKeyValidators.valid_key_material?(value),
        do: [],
        else: [{field, "must be a canonical base64-encoded WireGuard key"}]
    end)
  end
end
