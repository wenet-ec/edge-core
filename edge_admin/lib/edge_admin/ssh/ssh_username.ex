# edge_admin/lib/edge_admin/ssh/ssh_username.ex
defmodule EdgeAdmin.Ssh.SshUsername do
  @moduledoc false
  use EdgeAdmin.Schema

  @derive {
    Flop.Schema,
    filterable: [:username, :node_id, :inserted_at],
    sortable: [:username, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "ssh_usernames" do
    field(:username, :string)
    field(:password_hash, :string)
    field(:has_password, :boolean, virtual: true)

    # Associations
    belongs_to(:node, EdgeAdmin.Nodes.Node)
    has_many(:ssh_public_keys, EdgeAdmin.Ssh.SshPublicKey, on_delete: :delete_all)

    timestamps()
  end

  @doc """
  Returns whether this SSH username has a password configured.
  """
  def has_password?(%__MODULE__{password_hash: nil}), do: false
  def has_password?(%__MODULE__{password_hash: _hash}), do: true

  @doc false
  def changeset(ssh_username, attrs) do
    ssh_username
    |> cast(attrs, [:username, :password_hash, :node_id])
    |> validate_required([:username, :node_id])
    |> validate_length(:username, min: 3, max: 32)
    |> unique_constraint([:username, :node_id], name: :ssh_usernames_node_id_username_index)
    |> foreign_key_constraint(:node_id)
  end
end
