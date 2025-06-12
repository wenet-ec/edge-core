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

      iex> get("node_id")
      "abc123"

      iex> get("nonexistent")
      nil

      iex> get("node_id", "default_value")
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

      iex> set("node_id", "abc123")
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

      iex> delete("node_id")
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
      %{"node_id" => "abc123", "node_id_type" => "machine_id"}

  """
  def all do
    Setting
    |> Repo.all()
    |> Enum.into(%{}, fn %Setting{key: key, value: value} -> {key, value} end)
  end

  @doc """
  Checks if a key exists.

  ## Examples

      iex> has_key?("node_id")
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
  Gets the node ID.

  ## Examples

      iex> get_node_id()
      "bc9ebeb196a44dfd953e899a61637577"

      iex> get_node_id()
      nil

  """
  def get_node_id do
    get("node_id")
  end

  @doc """
  Gets the node ID type.

  ## Examples

      iex> get_node_id_type()
      "machine_id"

      iex> get_node_id_type()
      nil

  """
  def get_node_id_type do
    get("node_id_type")
  end

  @doc """
  Sets the node identity (both ID and type).

  ## Examples

      iex> set_node_identity("abc123", "machine_id")
      {:ok, %{node_id: "abc123", node_id_type: "machine_id"}}

      iex> set_node_identity("", "machine_id")
      {:error, "Node ID cannot be empty"}

  """
  def set_node_identity(node_id, node_id_type) do
    with :ok <- validate_node_identity(node_id, node_id_type),
         {:ok, _} <- set("node_id", node_id),
         {:ok, _} <- set("node_id_type", node_id_type) do
      {:ok, %{node_id: node_id, node_id_type: node_id_type}}
    else
      {:error, reason} -> {:error, reason}
      error -> error
    end
  end

  @doc """
  Gets the complete node identity as a map.

  ## Examples

      iex> get_node_identity()
      %{node_id: "abc123", node_id_type: "machine_id"}

      iex> get_node_identity()
      %{node_id: nil, node_id_type: nil}

  """
  def get_node_identity do
    %{
      node_id: get_node_id(),
      node_id_type: get_node_id_type()
    }
  end

  @doc """
  Checks if node identity is configured.

  ## Examples

      iex> node_identity_configured?()
      true

      iex> node_identity_configured?()
      false

  """
  def node_identity_configured? do
    get_node_id() != nil && get_node_id_type() != nil
  end

  @doc """
  Clears the node identity (useful for testing or reset scenarios).

  ## Examples

      iex> clear_node_identity()
      {:ok, :cleared}

  """
  def clear_node_identity do
    with {:ok, _} <- delete("node_id"),
         {:ok, _} <- delete("node_id_type") do
      {:ok, :cleared}
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
end
