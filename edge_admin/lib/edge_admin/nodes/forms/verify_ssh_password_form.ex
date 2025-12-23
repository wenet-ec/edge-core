# edge_admin/lib/edge_admin/nodes/forms/verify_ssh_password_form.ex
defmodule EdgeAdmin.Nodes.Forms.VerifySshPasswordForm do
  @moduledoc """
  Form for validating SSH password verification requests from agents.

  Validates that username and password are provided. Does not validate
  length constraints since these are values from SSH clients attempting
  authentication - if they don't match database records, verification
  will simply return false.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:username, :string)
    field(:password, :string)
  end

  @doc """
  Validates SSH password verification parameters.

  ## Validations
  - `username` - Required
  - `password` - Required

  ## Returns
  - `{:ok, attrs}` - Validated attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(%{"ssh_username" => ssh_username_attrs}) when is_map(ssh_username_attrs) do
    # unwrap ssh_username
    changeset(ssh_username_attrs)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password])
    |> validate_required([:username, :password])
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:ssh_username, "is required")
     |> apply_action!(:insert)}
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "username" => form.username,
      "password" => form.password
    }
  end
end
