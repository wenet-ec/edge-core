# edge_agent/lib/edge_agent/settings/settings.ex
defmodule EdgeAgent.Settings do
  @moduledoc """
  Public API for agent-side settings.

  Settings come in two flavours, each backed by its own engine:

  - **Config** — durable, sqlite-backed key-value. Survives restarts. Used for
    identity and discovery state (node_id, admin_urls, enrollment_verified,
    etc.). Engine: `EdgeAgent.Settings.Configs`.
  - **Secret** — session-scoped, in-memory via `:persistent_term`. Lives for
    the lifetime of the BEAM and is repopulated by bootstrap on the next
    start. Used for the API token and proxy password. Engine:
    `EdgeAgent.Settings.Secrets`.

  Generic accessors (`get_config/2`, `set_config/2`, `get_secret/2`,
  `set_secret/2`) exist mainly for tests and the typed accessors below.
  Application code should prefer the typed accessors (`get_api_token/0`,
  `get_admin_urls/0`, etc.) so the engine choice for each well-known key
  cannot be mistaken at the call site.

  ## Examples

      # Typed accessors (preferred)
      iex> Settings.set_node_id("a1b2c3d4-...")
      iex> Settings.get_node_id()
      "a1b2c3d4-..."

      iex> Settings.set_api_token("tok-abc")
      iex> Settings.get_api_token()
      "tok-abc"

      # Generic accessors
      iex> Settings.set_config("custom_key", "custom_value")
      iex> Settings.get_config("custom_key")
      "custom_value"

      iex> Settings.set_secret("custom_secret", "shhh")
      iex> Settings.get_secret("custom_secret")
      "shhh"
  """

  alias EdgeAgent.Settings.Configs
  alias EdgeAgent.Settings.Schemas.Setting
  alias EdgeAgent.Settings.Secrets

  # =============================================================================
  # Generic Config (sqlite)
  # =============================================================================

  @spec get_config(String.t()) :: String.t() | nil
  @spec get_config(String.t(), default) :: String.t() | default when default: any()
  def get_config(key, default \\ nil), do: Configs.get(key, default)

  @spec set_config(String.t(), String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_config(key, value), do: Configs.set(key, value)

  @spec delete_config(String.t()) :: {:ok, Setting.t() | nil} | {:error, Ecto.Changeset.t()}
  def delete_config(key), do: Configs.delete(key)

  @spec has_config?(String.t()) :: boolean()
  def has_config?(key), do: Configs.has_key?(key)

  @spec all_configs() :: %{String.t() => String.t()}
  def all_configs, do: Configs.all()

  # =============================================================================
  # Generic Secret (persistent_term)
  # =============================================================================

  @spec get_secret(String.t()) :: String.t() | nil
  @spec get_secret(String.t(), default) :: String.t() | default when default: any()
  def get_secret(key, default \\ nil), do: Secrets.get(key, default)

  @spec set_secret(String.t(), String.t()) :: :ok
  def set_secret(key, value), do: Secrets.set(key, value)

  @spec delete_secret(String.t()) :: :ok
  def delete_secret(key), do: Secrets.delete(key)

  @spec has_secret?(String.t()) :: boolean()
  def has_secret?(key), do: Secrets.has_key?(key)

  # =============================================================================
  # Typed Accessors — Config (durable)
  # =============================================================================

  @spec get_node_id() :: String.t() | nil
  def get_node_id, do: get_config("node_id")

  @spec set_node_id(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_node_id(value), do: set_config("node_id", value)

  @spec get_id_type() :: String.t() | nil
  def get_id_type, do: get_config("id_type")

  @spec set_id_type(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_id_type(value), do: set_config("id_type", value)

  @spec get_admin_urls() :: [String.t()]
  def get_admin_urls do
    case get_config("admin_urls") do
      nil ->
        []

      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, urls} when is_list(urls) -> urls
          _ -> []
        end
    end
  end

  @spec set_admin_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_admin_urls(urls) when is_list(urls) do
    case Jason.encode(urls) do
      {:ok, json} -> set_config("admin_urls", json)
      {:error, _} -> {:error, "Failed to encode admin URLs"}
    end
  end

  @spec get_netmaker_key() :: String.t() | nil
  def get_netmaker_key, do: get_config("netmaker_key")

  @spec set_netmaker_key(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_netmaker_key(value), do: set_config("netmaker_key", value)

  @spec get_last_check_self_update_at() :: DateTime.t() | nil
  def get_last_check_self_update_at do
    case get_config("last_check_self_update_at") do
      nil ->
        nil

      iso_string when is_binary(iso_string) ->
        case DateTime.from_iso8601(iso_string) do
          {:ok, dt, _offset} -> dt
          {:error, _} -> nil
        end
    end
  end

  @spec set_last_check_self_update_at(DateTime.t()) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_last_check_self_update_at(%DateTime{} = datetime) do
    iso_string = DateTime.to_iso8601(datetime)
    set_config("last_check_self_update_at", iso_string)
  end

  @spec get_enrollment_verified() :: boolean()
  def get_enrollment_verified do
    get_config("enrollment_verified") == "true"
  end

  @spec set_enrollment_verified(boolean()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_enrollment_verified(value) when is_boolean(value) do
    set_config("enrollment_verified", to_string(value))
  end

  @spec get_admin_fallback_urls() :: [String.t()]
  def get_admin_fallback_urls do
    case get_config("admin_fallback_urls") do
      nil ->
        []

      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, urls} when is_list(urls) -> urls
          _ -> []
        end
    end
  end

  @spec set_admin_fallback_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_admin_fallback_urls(urls) when is_list(urls) do
    case Jason.encode(urls) do
      {:ok, json} -> set_config("admin_fallback_urls", json)
      {:error, _} -> {:error, "Failed to encode admin fallback URLs"}
    end
  end

  @spec get_derp_map_url() :: String.t() | nil
  def get_derp_map_url, do: get_config("derp_map_url")

  @spec set_derp_map_url(String.t() | nil) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_derp_map_url(nil), do: delete_config("derp_map_url")
  def set_derp_map_url(url) when is_binary(url), do: set_config("derp_map_url", url)

  # =============================================================================
  # Typed Accessors — Secret (session-scoped)
  # =============================================================================

  @spec get_api_token() :: String.t() | nil
  def get_api_token, do: get_secret("api_token")

  @spec set_api_token(String.t()) :: :ok
  def set_api_token(value), do: set_secret("api_token", value)

  @spec get_proxy_password() :: String.t() | nil
  def get_proxy_password, do: get_secret("proxy_password")

  @spec set_proxy_password(String.t()) :: :ok
  def set_proxy_password(value), do: set_secret("proxy_password", value)
end
