# edge_admin/lib/edge_admin/ssh/forms/create_ssh_username_form.ex
defmodule EdgeAdmin.Ssh.Forms.CreateSshUsernameForm do
  @moduledoc """
  Form for validating SSH username creation inputs.

  Handles input validation for creating an SSH username, optionally with nested public keys.
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Ssh.Forms.CreateSshPublicKeyForm

  embedded_schema do
    field(:username, :string)
    field(:password, :string)
  end

  @doc """
  Validates and normalizes SSH username creation parameters.

  Note: node_id is validated at the controller level via path param and passed
  by the context function.

  ## Validations
  - `username` - Required, 3-32 characters
  - `password` - Optional, 12-128 characters if provided
  - `public_keys` - Optional array of public keys (validated individually)

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(%{"ssh_username" => ssh_username_attrs}) when is_map(ssh_username_attrs) do
    # Unwrap ssh_username
    changeset(ssh_username_attrs)
  end

  def changeset(attrs) when is_map(attrs) do
    # Extract public_keys for separate validation
    {public_keys_attrs, username_attrs} =
      Map.pop(attrs, "public_keys", [])

    with {:ok, validated_username} <- validate_username(username_attrs),
         {:ok, validated_keys} <- validate_public_keys(public_keys_attrs) do
      # Combine validated data
      result =
        if Enum.empty?(validated_keys) do
          validated_username
        else
          Map.put(validated_username, "public_keys", validated_keys)
        end

      {:ok, result}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:ssh_username, "is required")
     |> apply_action!(:insert)}
  end

  defp validate_username(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password])
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 32)
    |> validate_length(:password, min: 12, max: 128)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validate_public_keys([]), do: {:ok, []}

  defp validate_public_keys(keys_attrs) when is_list(keys_attrs) do
    # Validate each key individually
    results =
      keys_attrs
      |> Enum.with_index()
      |> Enum.map(fn {key_attrs, index} ->
        case CreateSshPublicKeyForm.changeset(key_attrs) do
          {:ok, validated_key} -> {:ok, validated_key}
          {:error, changeset} -> {:error, {index, changeset}}
        end
      end)

    # Check if all validations passed
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      validated_keys = Enum.map(results, fn {:ok, key} -> key end)
      {:ok, validated_keys}
    else
      # Build error changeset with indexed errors
      changeset = cast(%__MODULE__{}, %{}, [])

      changeset =
        Enum.reduce(errors, changeset, fn {:error, {index, key_changeset}}, acc ->
          # Add errors with field prefix
          Enum.reduce(key_changeset.errors, acc, fn {field, {message, opts}}, inner_acc ->
            add_error(inner_acc, :public_keys, "key #{index}: #{field} #{message}", opts)
          end)
        end)

      # Return the invalid changeset without raising, so callers can render errors
      {:error, elem(apply_action(changeset, :insert), 1)}
    end
  end

  defp validate_public_keys(_) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:public_keys, "must be an array")
     |> apply_action!(:insert)}
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "username" => form.username,
      "password" => form.password
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
