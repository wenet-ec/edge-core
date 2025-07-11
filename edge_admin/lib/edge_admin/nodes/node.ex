# edge_admin/lib/edge_admin/nodes/node.ex
defmodule EdgeAdmin.Nodes.Node do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "nodes" do
    field(:status, :string)
    field(:vpn_ip, :string)
    field(:last_seen_at, :utc_datetime)
    field(:id_type, :string)

    # Virtual field - computed from UUID
    field(:vpn_hostname, :string, virtual: true)

    # Associations
    has_many(:ssh_usernames, EdgeAdmin.Nodes.SshUsername, on_delete: :delete_all)
    has_many(:command_executions, EdgeAdmin.Commands.CommandExecution, on_delete: :nilify_all)
    has_many(:commands, through: [:command_executions, :command])

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:id, :vpn_ip, :last_seen_at, :status, :id_type])
    |> validate_uuid_format(:id)
    |> validate_required([:id])
    |> validate_inclusion(:id_type, ["machine_id", "hardware_id", "temporary_id"])
    |> unique_constraint(:id, name: :nodes_pkey)
    |> put_vpn_hostname()
  end

  defp validate_uuid_format(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID format"}]
      end
    end)
  end

  defp put_vpn_hostname(%Ecto.Changeset{} = changeset) do
    case get_change(changeset, :id) || get_field(changeset, :id) do
      nil -> changeset
      id -> put_change(changeset, :vpn_hostname, "node-#{id}")
    end
  end

  def vpn_hostname(%__MODULE__{id: id}) when not is_nil(id) do
    "node-#{id}"
  end

  def vpn_hostname(_), do: nil

  def populate_virtual_fields(%__MODULE__{} = node) do
    %{node | vpn_hostname: vpn_hostname(node)}
  end

  def temporary?(%__MODULE__{id_type: "temporary_id"}), do: true
  def temporary?(_), do: false

  def persistent?(%__MODULE__{id_type: id_type}) when id_type in ["machine_id", "hardware_id"],
    do: true

  def persistent?(_), do: false
end
