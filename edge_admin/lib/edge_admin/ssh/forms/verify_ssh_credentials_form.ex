# edge_admin/lib/edge_admin/ssh/forms/verify_ssh_credentials_form.ex
defmodule EdgeAdmin.Ssh.Forms.VerifySshCredentialsForm do
  @moduledoc """
  Form for validating SSH credentials verification requests from agents.

  Validates that username is provided with either a password or a public key,
  but not both.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Ssh.Validators.CredentialRequestValidators

  embedded_schema do
    field(:username, :string)
    field(:password, :string)
    field(:public_key, :string)
  end

  @doc """
  Validates SSH credentials verification parameters.

  Exactly one credential field must be present.
  """
  def changeset(attrs, opts \\ [])

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
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_credential_provided(changeset) do
    password = get_field(changeset, :password)
    public_key = get_field(changeset, :public_key)

    case CredentialRequestValidators.error(password, public_key) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :base, message)
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
