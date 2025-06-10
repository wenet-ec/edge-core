# edge_admin/lib/edge_admin/nodes/node.ex
defmodule EdgeAdmin.Nodes.Node do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "nodes" do
    field :status, :string
    field :hardware_id, :string
    field :vpn_ip, :string
    field :last_seen_at, :utc_datetime

    # Virtual field - computed from UUID
    field :vpn_hostname, :string, virtual: true

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:hardware_id, :vpn_ip, :last_seen_at, :status])
    |> validate_required([:hardware_id])
    |> unique_constraint(:hardware_id)
    |> put_vpn_hostname()
  end

  # Private function to compute and set the virtual vpn_hostname field during changesets
  defp put_vpn_hostname(%Ecto.Changeset{data: %{id: id}} = changeset) when not is_nil(id) do
    put_change(changeset, :vpn_hostname, "node-#{id}")
  end

  defp put_vpn_hostname(changeset), do: changeset

  @doc """
  Computes the VPN hostname for a node.
  Returns "node-{uuid}" format.
  """
  def vpn_hostname(%__MODULE__{id: id}) when not is_nil(id) do
    "node-#{id}"
  end

  def vpn_hostname(_), do: nil

  @doc """
  Populate virtual field after any database operation.
  """
  def populate_virtual_fields(%__MODULE__{} = node) do
    %{node | vpn_hostname: vpn_hostname(node)}
  end
end
