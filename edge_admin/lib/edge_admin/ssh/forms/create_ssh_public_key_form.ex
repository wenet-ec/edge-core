# edge_admin/lib/edge_admin/ssh/forms/create_ssh_public_key_form.ex
defmodule EdgeAdmin.Ssh.Forms.CreateSshPublicKeyForm do
  @moduledoc """
  Form for validating SSH public key creation inputs.

  Handles input validation for creating an SSH public key.
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  embedded_schema do
    field(:key_name, :string)
    field(:public_key, :string)
  end

  @doc """
  Validates and normalizes SSH public key creation parameters.

  Handles both:
  - Nested in SSH username creation: `%{"key_name" => ..., "public_key" => ...}`
  - Standalone endpoint: `%{"ssh_public_key" => %{"key_name" => ..., "public_key" => ...}}`

  ## Validations
  - `key_name` - Required, human-readable name for the key
  - `public_key` - Required, must be valid SSH public key format

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(attrs) when is_map(attrs) do
    # Nested in SSH username or already unwrapped
    %__MODULE__{}
    |> cast(attrs, [:key_name, :public_key])
    |> validate_required([:key_name, :public_key])
    |> validate_length(:key_name, min: 1, max: 255)
    |> validate_ssh_public_key_format()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_ssh_public_key_format(changeset) do
    validate_change(changeset, :public_key, fn :public_key, public_key ->
      case SshPublicKey.validate_key_format(public_key) do
        {:ok, _algorithm} -> []
        {:error, reason} -> [public_key: reason]
      end
    end)
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "key_name" => form.key_name,
      "public_key" => form.public_key
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
