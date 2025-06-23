# edge_admin/lib/edge_admin/nodes/ssh_public_key.ex
defmodule EdgeAdmin.Nodes.SshPublicKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ssh_public_keys" do
    field(:public_key, :string)
    field(:key_name, :string)

    # Associations
    belongs_to(:ssh_username, EdgeAdmin.Nodes.SshUsername)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ssh_public_key, attrs) do
    ssh_public_key
    |> cast(attrs, [:public_key, :key_name, :ssh_username_id])
    |> validate_required([:public_key, :key_name, :ssh_username_id])
    |> unique_constraint([:ssh_username_id, :key_name])
    |> foreign_key_constraint(:ssh_username_id)
  end
end
