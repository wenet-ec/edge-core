# edge_admin/lib/edge_admin/ssh/schemas/ssh_public_key.ex
defmodule EdgeAdmin.Ssh.Schemas.SshPublicKey do
  @moduledoc "Ecto schema for an authorized SSH public key."
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdmin.Ssh.Validators.SshPublicKeyValidators

  @type t :: %__MODULE__{
          id: String.t() | nil,
          public_key: String.t() | nil,
          key_name: String.t() | nil,
          ssh_username_id: String.t() | nil,
          ssh_username: SshUsername.t() | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {
    Flop.Schema,
    filterable: [:key_name, :public_key, :ssh_username_id, :inserted_at, :updated_at],
    sortable: [:key_name, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "ssh_public_keys" do
    field(:public_key, :string)
    field(:key_name, :string)

    belongs_to(:ssh_username, SshUsername)

    timestamps()
  end

  @doc "Builds a changeset for creating or updating an SSH public key."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(ssh_public_key, attrs) do
    ssh_public_key
    |> cast(attrs, [:public_key, :key_name, :ssh_username_id])
    |> validate_required([:public_key, :key_name, :ssh_username_id])
    |> validate_key_name()
    |> validate_ssh_public_key()
    |> unique_constraint([:key_name, :ssh_username_id], name: :ssh_public_keys_ssh_username_id_key_name_index)
    |> foreign_key_constraint(:ssh_username_id)
  end

  defp validate_key_name(changeset) do
    validate_change(changeset, :key_name, fn :key_name, value ->
      case SshPublicKeyValidators.key_name_error(value) do
        :ok -> []
        {:error, message} -> [key_name: message]
      end
    end)
  end

  defp validate_ssh_public_key(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      case SshPublicKeyValidators.validate_key_format(public_key) do
        {:ok, _algorithm} ->
          []

        {:error, "invalid SSH key format"} ->
          [public_key: "must be a valid SSH public key format (algorithm base64data [comment])"]

        {:error, reason} ->
          [public_key: reason]
      end
    end)
  end

  @doc "Returns the list of supported SSH key algorithms."
  @spec supported_algorithms() :: [String.t()]
  def supported_algorithms, do: SshPublicKeyValidators.supported_algorithms()

  @doc "Validates a public key string's format, algorithm, and base64 data."
  @spec validate_key_format(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_key_format(public_key), do: SshPublicKeyValidators.validate_key_format(public_key)
end
