# edge_admin/lib/edge_admin/nodes/ssh_username.ex
defmodule EdgeAdmin.Nodes.SshUsername do
  @moduledoc false
  use EdgeAdmin.Schema

  schema "ssh_usernames" do
    field(:username, :string)
    field(:password, :string)

    # Associations
    belongs_to(:node, EdgeAdmin.Nodes.Node)
    has_many(:ssh_public_keys, EdgeAdmin.Nodes.SshPublicKey, on_delete: :delete_all)

    timestamps()
  end

  @doc false
  def changeset(ssh_username, attrs) do
    ssh_username
    |> cast(attrs, [:username, :password, :node_id])
    |> validate_required([:username, :node_id])
    |> unique_constraint([:username, :node_id], name: :ssh_usernames_node_id_username_index)
    |> foreign_key_constraint(:node_id)
  end
end
