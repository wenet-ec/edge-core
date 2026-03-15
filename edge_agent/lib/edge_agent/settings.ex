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
  - `admin_urls` - JSON-encoded list of admin server URLs (discovered via VPN)

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
  Get the LAN DNS authority domain (e.g. "edge.local").

  Injected by admin at registration. Returns nil if not yet received.
  """
  @spec get_lan_domain() :: String.t() | nil
  def get_lan_domain, do: get("lan_domain")

  @doc """
  Set the LAN DNS authority domain.
  """
  @spec set_lan_domain(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_lan_domain(value), do: set("lan_domain", value)

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

  @doc """
  Get the Netmaker enrollment key for VPN join.

  Stored after a successful admin enrollment key verification so the agent
  can rejoin the VPN on restart without re-verifying.
  """
  @spec get_netmaker_key() :: String.t() | nil
  def get_netmaker_key, do: get("netmaker_key")

  @doc """
  Set the Netmaker enrollment key.
  """
  @spec set_netmaker_key(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_netmaker_key(value), do: set("netmaker_key", value)

  @doc """
  Get the last self-update check timestamp.

  Returns a DateTime when the agent last checked for self-updates,
  or nil if never checked.
  """
  @spec get_last_check_self_update_at() :: DateTime.t() | nil
  def get_last_check_self_update_at do
    case get("last_check_self_update_at") do
      nil ->
        nil

      iso_string when is_binary(iso_string) ->
        case DateTime.from_iso8601(iso_string) do
          {:ok, dt, _offset} -> dt
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Get whether enrollment has been verified.

  Returns true if the agent has successfully verified an enrollment key and
  joined the VPN at least once. Used to skip re-verification on restarts
  when the VPN connection is still healthy.
  """
  @spec get_enrollment_verified() :: boolean()
  def get_enrollment_verified do
    get("enrollment_verified") == "true"
  end

  @doc """
  Set whether enrollment has been verified.
  """
  @spec set_enrollment_verified(boolean()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_enrollment_verified(value) when is_boolean(value) do
    set("enrollment_verified", to_string(value))
  end

  @doc """
  Get admin fallback URLs as a list.

  These are the URLs embedded in the enrollment key blob and stored on first
  successful verify. Used when VPN is down and no admin URLs are in Settings.
  Falls back to empty list if not set.
  """
  @spec get_admin_fallback_urls() :: [String.t()]
  def get_admin_fallback_urls do
    case get("admin_fallback_urls") do
      nil ->
        []

      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, urls} when is_list(urls) -> urls
          _ -> []
        end

      _ ->
        []
    end
  end

  @doc """
  Set admin fallback URLs.

  Stores the URLs from the enrollment key blob so the agent can reach admin
  when VPN is down.
  """
  @spec set_admin_fallback_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_admin_fallback_urls(urls) when is_list(urls) do
    case Jason.encode(urls) do
      {:ok, json} -> set("admin_fallback_urls", json)
      {:error, _} -> {:error, "Failed to encode admin fallback URLs"}
    end
  end

  @doc """
  Set the last self-update check timestamp.

  Stores the datetime when the agent last checked for self-updates.
  Accepts a DateTime struct and stores it as an ISO8601 string.

  Note: Always pass `DateTime.truncate(DateTime.utc_now(), :second)` to ensure
  second precision matching admin's `:utc_datetime` format.
  """
  @spec set_last_check_self_update_at(DateTime.t()) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_last_check_self_update_at(%DateTime{} = datetime) do
    iso_string = DateTime.to_iso8601(datetime)
    set("last_check_self_update_at", iso_string)
  end
end
