# edge_agent/lib/edge_agent/settings.ex
defmodule EdgeAgent.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias EdgeAgent.Repo

  alias EdgeAgent.Settings.Setting

  @doc """
  Returns the list of settings.

  ## Examples

      iex> list_settings()
      [%Setting{}, ...]

  """
  def list_settings do
    Repo.all(Setting)
  end

  @doc """
  Gets a single setting.

  Raises `Ecto.NoResultsError` if the Setting does not exist.

  ## Examples

      iex> get_setting!(123)
      %Setting{}

      iex> get_setting!(456)
      ** (Ecto.NoResultsError)

  """
  def get_setting!(id), do: Repo.get!(Setting, id)

  @doc """
  Creates a setting.

  ## Examples

      iex> create_setting(%{field: value})
      {:ok, %Setting{}}

      iex> create_setting(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_setting(attrs \\ %{}) do
    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a setting.

  ## Examples

      iex> update_setting(setting, %{field: new_value})
      {:ok, %Setting{}}

      iex> update_setting(setting, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_setting(%Setting{} = setting, attrs) do
    setting
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a setting.

  ## Examples

      iex> delete_setting(setting)
      {:ok, %Setting{}}

      iex> delete_setting(setting)
      {:error, %Ecto.Changeset{}}

  """
  def delete_setting(%Setting{} = setting) do
    Repo.delete(setting)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking setting changes.

  ## Examples

      iex> change_setting(setting)
      %Ecto.Changeset{data: %Setting{}}

  """
  def change_setting(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  @doc """
  Gets a value by key.

  ## Examples

      iex> get("id")
      "abc123"

      iex> get("nonexistent")
      nil

      iex> get("id", "default_value")
      "abc123"

  """
  def get(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> default
    end
  end

  @doc """
  Sets a key-value pair. Creates if doesn't exist, updates if it does.

  ## Examples

      iex> set("id", "abc123")
      {:ok, %Setting{}}

      iex> set("", "value")
      {:error, %Ecto.Changeset{}}

  """
  def set(key, value) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        create_setting(%{key: key, value: value})

      existing ->
        update_setting(existing, %{value: value})
    end
  end

  @doc """
  Deletes a setting by key.

  ## Examples

      iex> delete("id")
      {:ok, %Setting{}}

      iex> delete("nonexistent")
      {:ok, nil}

  """
  def delete(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:ok, nil}
      setting -> delete_setting(setting)
    end
  end

  @doc """
  Returns all settings as a map.

  ## Examples

      iex> all()
      %{"id" => "abc123", "id_type" => "machine_id"}

  """
  def all do
    Setting
    |> Repo.all()
    |> Enum.into(%{}, fn %Setting{key: key, value: value} -> {key, value} end)
  end

  @doc """
  Checks if a key exists.

  ## Examples

      iex> has_key?("id")
      true

      iex> has_key?("nonexistent")
      false

  """
  def has_key?(key) do
    Setting
    |> where([s], s.key == ^key)
    |> Repo.exists?()
  end

  @doc """
  Sets the node identity (both ID and type), normalizing the node_id to UUID format.

  ## Examples

      iex> set_node_identity("abc123", "machine_id")
      {:ok, %{id: "abc123", id_type: "machine_id"}}

      iex> set_node_identity("", "machine_id")
      {:error, "Node ID cannot be empty"}

  """
  def set_node_identity(node_id, node_id_type) do
    with :ok <- validate_node_identity(node_id, node_id_type),
         {:ok, normalized_id} <- normalize_node_id(node_id),
         {:ok, _} <- set("id", normalized_id),
         {:ok, _} <- set("id_type", node_id_type) do
      {:ok, %{id: normalized_id, id_type: node_id_type}}
    else
      {:error, reason} -> {:error, reason}
      error -> error
    end
  end

  # PRIVATE FUNCTIONS

  defp validate_node_identity(node_id, node_id_type) do
    cond do
      is_nil(node_id) or String.trim(node_id) == "" ->
        {:error, "Node ID cannot be empty"}

      is_nil(node_id_type) or String.trim(node_id_type) == "" ->
        {:error, "Node ID type cannot be empty"}

      node_id_type not in ["machine_id", "hardware_id", "temporary_id"] ->
        {:error, "Invalid node ID type. Must be one of: machine_id, hardware_id, temporary_id"}

      String.length(node_id) > 255 ->
        {:error, "Node ID too long (max 255 characters)"}

      true ->
        :ok
    end
  end

  defp normalize_node_id(node_id) do
    case Ecto.UUID.cast(node_id) do
      {:ok, uuid} ->
        # Already in proper format
        {:ok, uuid}

      :error ->
        # Try to convert from 32-char hex to UUID format
        case format_hex_to_uuid(node_id) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, "Invalid node ID format"}
        end
    end
  end

  defp format_hex_to_uuid(hex_string) do
    # Remove any existing dashes and convert to lowercase
    clean_hex =
      hex_string
      |> String.replace("-", "")
      |> String.downcase()

    # Check if it's a valid 32-character hex string
    if String.match?(clean_hex, ~r/^[a-f0-9]{32}$/) do
      # Insert dashes at proper UUID positions: 8-4-4-4-12
      uuid =
        String.slice(clean_hex, 0, 8) <>
          "-" <>
          String.slice(clean_hex, 8, 4) <>
          "-" <>
          String.slice(clean_hex, 12, 4) <>
          "-" <>
          String.slice(clean_hex, 16, 4) <>
          "-" <>
          String.slice(clean_hex, 20, 12)

      {:ok, uuid}
    else
      :error
    end
  end
end
