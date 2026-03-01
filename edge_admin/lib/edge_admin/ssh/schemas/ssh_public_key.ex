# edge_admin/lib/edge_admin/ssh/schemas/ssh_public_key.ex
defmodule EdgeAdmin.Ssh.Schemas.SshPublicKey do
  @moduledoc false
  use EdgeAdmin.Schema

  @type t :: %__MODULE__{}

  # Supported SSH key algorithms
  @supported_algorithms [
    "ssh-ed25519",
    "ecdsa-sha2-nistp256",
    "ecdsa-sha2-nistp384",
    "ecdsa-sha2-nistp521",
    "ssh-rsa"
  ]

  # SSH key format regex - matches "algorithm base64data [comment]"
  @ssh_key_regex ~r/^(ssh-ed25519|ecdsa-sha2-nistp(?:256|384|521)|ssh-rsa)\s+([A-Za-z0-9+\/]+=*)\s*(.*)$/

  @derive {
    Flop.Schema,
    filterable: [:key_name, :public_key, :ssh_username_id, :inserted_at],
    sortable: [:key_name, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "ssh_public_keys" do
    field(:public_key, :string)
    field(:key_name, :string)

    # Associations
    belongs_to(:ssh_username, EdgeAdmin.Ssh.Schemas.SshUsername)

    timestamps()
  end

  @doc false
  def changeset(ssh_public_key, attrs) do
    ssh_public_key
    |> cast(attrs, [:public_key, :key_name, :ssh_username_id])
    |> validate_required([:public_key, :key_name, :ssh_username_id])
    |> validate_ssh_public_key_format()
    |> validate_ssh_key_algorithm()
    |> validate_base64_key_data()
    |> unique_constraint([:key_name, :ssh_username_id], name: :ssh_public_keys_ssh_username_id_key_name_index)
    |> foreign_key_constraint(:ssh_username_id)
  end

  # Validation functions

  defp validate_ssh_public_key_format(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      trimmed_key = String.trim(public_key)

      if Regex.match?(@ssh_key_regex, trimmed_key) do
        []
      else
        [public_key: "must be a valid SSH public key format (algorithm base64data [comment])"]
      end
    end)
  end

  defp validate_ssh_key_algorithm(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      case extract_algorithm(public_key) do
        {:ok, algorithm} ->
          if algorithm in @supported_algorithms do
            []
          else
            [
              public_key:
                "unsupported key algorithm '#{algorithm}'. Supported: #{Enum.join(@supported_algorithms, ", ")}"
            ]
          end

        {:error, reason} ->
          [public_key: reason]
      end
    end)
  end

  defp validate_base64_key_data(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      case extract_key_data(public_key) do
        {:ok, key_data} ->
          case Base.decode64(key_data, ignore: :whitespace) do
            {:ok, _decoded} -> []
            :error -> [public_key: "contains invalid base64 key data"]
          end

        {:error, _reason} ->
          # Already handled by format validation
          []
      end
    end)
  end

  # Helper functions

  defp extract_algorithm(public_key) do
    case Regex.run(@ssh_key_regex, String.trim(public_key)) do
      [_full, algorithm, _key_data, _comment] -> {:ok, algorithm}
      [_full, algorithm, _key_data] -> {:ok, algorithm}
      _ -> {:error, "invalid SSH key format"}
    end
  end

  defp extract_key_data(public_key) do
    case Regex.run(@ssh_key_regex, String.trim(public_key)) do
      [_full, _algorithm, key_data, _comment] -> {:ok, key_data}
      [_full, _algorithm, key_data] -> {:ok, key_data}
      _ -> {:error, "invalid SSH key format"}
    end
  end

  @doc """
  Returns the list of supported SSH key algorithms.
  """
  def supported_algorithms, do: @supported_algorithms

  @doc """
  Validates if a public key string has valid format and algorithm.
  Returns {:ok, algorithm} or {:error, reason}.
  """
  def validate_key_format(public_key) when is_binary(public_key) do
    trimmed_key = String.trim(public_key)

    with true <- Regex.match?(@ssh_key_regex, trimmed_key),
         {:ok, algorithm} <- extract_algorithm(trimmed_key),
         true <- algorithm in @supported_algorithms,
         {:ok, key_data} <- extract_key_data(trimmed_key),
         {:ok, _decoded} <- Base.decode64(key_data, ignore: :whitespace) do
      {:ok, algorithm}
    else
      false -> {:error, "invalid SSH key format"}
      {:error, reason} -> {:error, reason}
      :error -> {:error, "invalid base64 key data"}
    end
  end
end
