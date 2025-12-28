# edge_agent/lib/edge_agent/settings.ex
defmodule EdgeAgent.Settings do
  @moduledoc """
  Simple key-value settings storage for agent configuration.

  This module provides a persistent key-value store backed by the database for
  storing agent configuration and runtime state. Settings persist across restarts
  and are used for identity, authentication, and admin discovery.

  ## Key Concepts

  - **Key-Value Store**: Simple string key → string value mapping
  - **Database Persistence**: All settings stored in `settings` table
  - **Typed Accessors**: Convenience functions for common settings (node_id, api_token, etc.)
  - **JSON Encoding**: Complex values (lists) stored as JSON strings

  ## Common Settings

  - `node_id` - Agent's unique node identifier (UUID)
  - `id_type` - Type of ID ("persistent" or "random")
  - `api_token` - JWT token for authenticating with admin API
  - `proxy_password` - Password for proxy server authentication
  - `admin_urls` - JSON-encoded list of admin server URLs

  ## Architecture

  Settings are stored in a simple schema:
  ```
  CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
  ```

  The module provides:
  - Generic `get/2`, `set/2`, `delete/1` functions
  - Typed accessors for common settings (`get_node_id/0`, `set_api_token/1`, etc.)
  - Upsert semantics (insert if missing, update if exists)

  ## Examples

      # Generic key-value access
      iex> Settings.set("custom_key", "custom_value")
      {:ok, %Setting{}}
      iex> Settings.get("custom_key")
      "custom_value"

      # Typed accessors
      iex> Settings.set_node_id("a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809")
      {:ok, %Setting{}}
      iex> Settings.get_node_id()
      "a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809"

      # Admin URLs (stored as JSON)
      iex> Settings.set_admin_urls(["http://admin1:44000", "http://admin2:44000"])
      {:ok, %Setting{}}
      iex> Settings.get_admin_urls()
      ["http://admin1:44000", "http://admin2:44000"]

      # Check existence
      iex> Settings.has_key?("node_id")
      true

      # Get all settings
      iex> Settings.all()
      %{"node_id" => "...", "api_token" => "...", ...}
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Repo
  alias EdgeAgent.Settings.Setting

  @doc """
  Get a setting value by key.

  Returns the value if found, otherwise returns the default.
  """
  @spec get(String.t(), any()) :: String.t() | any()
  def get(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> default
    end
  end

  @doc """
  Set a setting value by key.

  Creates the setting if it doesn't exist, updates it if it does (upsert semantics).
  """
  @spec set(String.t(), String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set(key, value) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: value})
        |> Repo.insert()

      existing ->
        existing
        |> Setting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  @doc """
  Delete a setting by key.

  Returns `{:ok, nil}` if key doesn't exist, `{:ok, setting}` if deleted successfully.
  """
  @spec delete(String.t()) :: {:ok, Setting.t() | nil} | {:error, Ecto.Changeset.t()}
  def delete(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:ok, nil}
      setting -> Repo.delete(setting)
    end
  end

  @doc """
  Check if a setting key exists.
  """
  @spec has_key?(String.t()) :: boolean()
  def has_key?(key) do
    Setting
    |> where([s], s.key == ^key)
    |> Repo.exists?()
  end

  @doc """
  Get all settings as a map.

  Returns a map with keys as setting names and values as setting values.
  """
  @spec all() :: %{String.t() => String.t()}
  def all do
    Setting
    |> Repo.all()
    |> Map.new(fn %Setting{key: key, value: value} -> {key, value} end)
  end

  # =============================================================================
  # Typed Setting Accessors
  # =============================================================================

  @doc """
  Get the node ID.
  """
  @spec get_node_id() :: String.t() | nil
  def get_node_id, do: get("node_id")

  @doc """
  Set the node ID.
  """
  @spec set_node_id(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_node_id(value), do: set("node_id", value)

  @doc """
  Get the node ID type (persistent or random).
  """
  @spec get_id_type() :: String.t() | nil
  def get_id_type, do: get("id_type")

  @doc """
  Set the node ID type.
  """
  @spec set_id_type(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_id_type(value), do: set("id_type", value)

  @doc """
  Get the API token for admin authentication.
  """
  @spec get_api_token() :: String.t() | nil
  def get_api_token, do: get("api_token")

  @doc """
  Set the API token.
  """
  @spec set_api_token(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_api_token(value), do: set("api_token", value)

  @doc """
  Get the proxy password.
  """
  @spec get_proxy_password() :: String.t() | nil
  def get_proxy_password, do: get("proxy_password")

  @doc """
  Set the proxy password.
  """
  @spec set_proxy_password(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_proxy_password(value), do: set("proxy_password", value)

  @doc """
  Get admin URLs as a list.

  Returns a list of admin URL strings, or empty list if not set.
  The URLs are stored as a JSON-encoded string.
  """
  @spec get_admin_urls() :: [String.t()]
  def get_admin_urls do
    case get("admin_urls") do
      nil ->
        []

      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, urls} when is_list(urls) -> urls
          _ -> []
        end

      urls when is_list(urls) ->
        urls

      _ ->
        []
    end
  end

  @doc """
  Set admin URLs.

  Accepts a list of URL strings and stores them as JSON.
  """
  @spec set_admin_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_admin_urls(urls) when is_list(urls) do
    case Jason.encode(urls) do
      {:ok, json} -> set("admin_urls", json)
      {:error, _} -> {:error, "Failed to encode admin URLs"}
    end
  end
end
