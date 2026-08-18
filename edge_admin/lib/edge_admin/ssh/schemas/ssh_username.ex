# edge_admin/lib/edge_admin/ssh/schemas/ssh_username.ex
defmodule EdgeAdmin.Ssh.Schemas.SshUsername do
  @moduledoc "Ecto schema for an SSH username assigned to an edge node."
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Validators.SshUsernameValidators

  @type t :: %__MODULE__{
          id: String.t() | nil,
          username: String.t() | nil,
          password_hash: String.t() | nil,
          has_password: boolean() | nil,
          node_id: String.t() | nil,
          node: Node.t() | NotLoaded.t(),
          ssh_public_keys: [SshPublicKey.t()] | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

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

    belongs_to(:node, Node)
    has_many(:ssh_public_keys, SshPublicKey, on_delete: :delete_all)

    timestamps()
  end

  @doc "Returns whether this SSH username has a password configured."
  @spec has_password?(t()) :: boolean()
  def has_password?(%__MODULE__{password_hash: nil}), do: false
  def has_password?(%__MODULE__{password_hash: _hash}), do: true

  @doc "Builds a changeset for creating or updating an SSH username."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(ssh_username, attrs) do
    ssh_username
    |> cast(attrs, [:username, :password_hash, :node_id])
    |> validate_required([:username, :node_id])
    |> validate_username()
    |> unique_constraint([:username, :node_id], name: :ssh_usernames_node_id_username_index)
    |> foreign_key_constraint(:node_id)
  end

  defp validate_username(changeset) do
    validate_change(changeset, :username, fn :username, value ->
      case SshUsernameValidators.username_error(value) do
        :ok -> []
        {:error, message} -> [username: message]
      end
    end)
  end
end
