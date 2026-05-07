# edge_admin/lib/edge_admin/ssh/schemas/ssh_username.ex
defmodule EdgeAdmin.Ssh.Schemas.SshUsername do
  @moduledoc false
  use EdgeAdmin.Schema

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  @type t :: %__MODULE__{}

  @derive {
    Flop.Schema,
    filterable: [:username, :node_id, :inserted_at, :updated_at],
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
    belongs_to(:node, EdgeAdmin.Nodes.Schemas.Node)
    has_many(:ssh_public_keys, SshPublicKey, on_delete: :delete_all)

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
    |> validate_length(:username, min: Naming.ssh_username_min_length(), max: Naming.ssh_username_max_length())
    |> validate_format(:username, Naming.ssh_username_regex(),
      message:
        "must start with a letter or underscore and contain only lowercase letters, digits, hyphens, or underscores"
    )
    |> unique_constraint([:username, :node_id], name: :ssh_usernames_node_id_username_index)
    |> foreign_key_constraint(:node_id)
  end
end
