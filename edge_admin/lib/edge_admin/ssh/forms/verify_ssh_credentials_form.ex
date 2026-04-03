# edge_admin/lib/edge_admin/ssh/forms/verify_ssh_credentials_form.ex
defmodule EdgeAdmin.Ssh.Forms.VerifySshCredentialsForm do
  @moduledoc """
  Form for validating SSH credentials verification requests from agents.

  Validates that username is provided along with either a password OR a public key
  (but not both). This unified form supports both password and public key authentication.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:username, :string)
    field(:password, :string)
    field(:public_key, :string)
  end

  @doc """
  Validates SSH credentials verification parameters.

  ## Validations
  - `username` - Required
  - `password` - Optional (mutually exclusive with public_key)
  - `public_key` - Optional (mutually exclusive with password)
  - At least one of password or public_key must be provided

  ## Returns
  - `{:ok, attrs}` - Validated attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(attrs, opts \\ [])

  def changeset(%{ssh_username: ssh_username_attrs}, opts) when is_map(ssh_username_attrs),
    do: changeset(ssh_username_attrs, opts)

  def changeset(attrs, _opts) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password, :public_key])
    |> validate_required([:username])
    |> validate_credential_provided()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params, _opts) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:ssh_username, "is required")
     |> apply_action!(:insert)}
  end

  defp validate_credential_provided(changeset) do
    password = get_field(changeset, :password)
    public_key = get_field(changeset, :public_key)

    cond do
      is_nil(password) and is_nil(public_key) ->
        add_error(changeset, :base, "either password or public_key must be provided")

      not is_nil(password) and not is_nil(public_key) ->
        add_error(changeset, :base, "only one of password or public_key should be provided")

      true ->
        changeset
    end
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "username" => form.username,
      "password" => form.password,
      "public_key" => form.public_key
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
