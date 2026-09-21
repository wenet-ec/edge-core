# edge_admin/lib/edge_admin/ingress_tunneling/schemas/tunnel_connection.ex
defmodule EdgeAdmin.IngressTunneling.Schemas.TunnelConnection do
  @moduledoc """
  A Tunnel client's connection to one selected Ingress Node.

  Tunnel addresses are allocated in the selected Ingress's isolated realm, so
  they are unique per Node rather than globally across all Ingresses.
  """
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Vpn

  @flop_options [
    filterable: [:tunnel_client_id, :node_id, :inserted_at, :updated_at],
    sortable: [:inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          tunnel_client_id: String.t(),
          node_id: String.t(),
          ingress_ipv4_address: String.t(),
          ingress_ipv6_address: String.t(),
          tunnel_ipv4_address: String.t(),
          tunnel_ipv6_address: String.t(),
          tunnel_client: TunnelClient.t() | NotLoaded.t(),
          node: Node.t() | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "tunnel_connections" do
    field(:ingress_ipv4_address, :string)
    field(:ingress_ipv6_address, :string)
    field(:tunnel_ipv4_address, :string)
    field(:tunnel_ipv6_address, :string)

    belongs_to(:tunnel_client, TunnelClient)
    belongs_to(:node, Node)

    timestamps()
  end

  @doc false
  def changeset(tunnel_connection, attrs) do
    tunnel_connection
    |> cast(attrs, [
      :tunnel_client_id,
      :node_id,
      :ingress_ipv4_address,
      :ingress_ipv6_address,
      :tunnel_ipv4_address,
      :tunnel_ipv6_address
    ])
    |> validate_required([
      :tunnel_client_id,
      :node_id,
      :ingress_ipv4_address,
      :ingress_ipv6_address,
      :tunnel_ipv4_address,
      :tunnel_ipv6_address
    ])
    |> validate_ipv4_address(:ingress_ipv4_address)
    |> validate_ipv6_address(:ingress_ipv6_address)
    |> validate_ipv4_address(:tunnel_ipv4_address)
    |> validate_ipv6_address(:tunnel_ipv6_address)
    |> unique_constraint([:tunnel_client_id, :node_id])
    |> unique_constraint([:node_id, :tunnel_ipv4_address])
    |> unique_constraint([:node_id, :tunnel_ipv6_address])
    |> foreign_key_constraint(:tunnel_client_id)
    |> foreign_key_constraint(:node_id)
  end

  defp validate_ipv4_address(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Vpn.parse_cidr(value) do
        {:ok, {_address, 32}} -> []
        _ -> [{field, "must be an IPv4 address with a /32 prefix"}]
      end
    end)
  end

  defp validate_ipv6_address(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Vpn.parse_ipv6_cidr(value) do
        {:ok, {_address, 128}} -> []
        _ -> [{field, "must be an IPv6 address with a /128 prefix"}]
      end
    end)
  end
end
