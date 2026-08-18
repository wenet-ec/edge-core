# edge_admin/lib/edge_admin/ssh/forms/create_ssh_username_form.ex
defmodule EdgeAdmin.Ssh.Forms.CreateSshUsernameForm do
  @moduledoc """
  Form for validating SSH username creation inputs.

  Validates external API input before passing it to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Ssh.Forms.CreateSshPublicKeyForm
  alias EdgeAdmin.Ssh.Validators.SshUsernameValidators

  embedded_schema do
    field(:username, :string)
    field(:password, :string)
  end

  @doc """
  Validates and normalizes SSH username creation parameters.

  `node_id` comes from path/context data, not this form. Nested public keys
  are validated individually.
  """
  def changeset(attrs) when is_map(attrs) do
    {public_keys_attrs, username_attrs} =
      case Map.pop(attrs, :public_keys) do
        {nil, _} -> Map.pop(attrs, "public_keys", [])
        result -> result
      end

    with {:ok, validated_username} <- validate_username(username_attrs),
         {:ok, validated_keys} <- validate_public_keys(public_keys_attrs) do
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
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_username(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username, :password])
    |> validate_required([:username])
    |> validate_username_field()
    |> validate_password()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validate_username_field(changeset) do
    validate_change(changeset, :username, fn :username, value ->
      case SshUsernameValidators.username_error(value) do
        :ok -> []
        {:error, message} -> [username: message]
      end
    end)
  end

  defp validate_password(changeset) do
    validate_change(changeset, :password, fn :password, value ->
      case SshUsernameValidators.password_error(value) do
        :ok -> []
        {:error, message} -> [password: message]
      end
    end)
  end

  defp validate_public_keys([]), do: {:ok, []}

  defp validate_public_keys(keys_attrs) when is_list(keys_attrs) do
    results =
      keys_attrs
      |> Enum.with_index()
      |> Enum.map(fn {key_attrs, index} ->
        case CreateSshPublicKeyForm.changeset(key_attrs) do
          {:ok, validated_key} -> {:ok, validated_key}
          {:error, changeset} -> {:error, {index, changeset}}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      validated_keys = Enum.map(results, fn {:ok, key} -> key end)
      {:ok, validated_keys}
    else
      changeset = cast(%__MODULE__{}, %{}, [])

      changeset =
        Enum.reduce(errors, changeset, fn {:error, {index, key_changeset}}, acc ->
          Enum.reduce(key_changeset.errors, acc, fn {field, {message, opts}}, inner_acc ->
            add_error(inner_acc, :public_keys, "key #{index}: #{field} #{message}", opts)
          end)
        end)

      {:error, elem(apply_action(changeset, :insert), 1)}
    end
  end

  defp validate_public_keys(_) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:public_keys, "must be an array")

    {:error, %{changeset | action: :insert}}
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
