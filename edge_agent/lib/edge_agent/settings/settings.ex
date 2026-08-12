# edge_agent/lib/edge_agent/settings/settings.ex
defmodule EdgeAgent.Settings do
  @moduledoc """
  Public API for agent-side settings.

  Settings come in two flavours, each backed by its own engine:

  - **Config** — durable, sqlite-backed key-value. Survives restarts. Used for
    identity and discovery state (node_id, admin_urls, enrollment_key_id, etc.).
    Engine: `EdgeAgent.Settings.Configs`.
  - **Secret** — session-scoped, in-memory via `:persistent_term`. Lives for
    the lifetime of the BEAM and is repopulated by bootstrap on the next
    start. Used for the proxy password. Engine: `EdgeAgent.Settings.Secrets`.

  Generic accessors (`get_config/2`, `set_config/2`, `get_secret/2`,
  `set_secret/2`) exist mainly for tests and the typed accessors below.
  Application code should prefer the typed accessors (`get_api_token/0`,
  `get_admin_urls/0`, etc.) so the engine choice for each well-known key
  cannot be mistaken at the call site.

  """

  alias EdgeAgent.Settings.Configs
  alias EdgeAgent.Settings.ConfigValueCodec
  alias EdgeAgent.Settings.Schemas.Setting
  alias EdgeAgent.Settings.Secrets

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

  @spec get_secret(String.t()) :: String.t() | nil
  @spec get_secret(String.t(), default) :: String.t() | default when default: any()
  def get_secret(key, default \\ nil), do: Secrets.get(key, default)

  @spec set_secret(String.t(), String.t()) :: :ok
  def set_secret(key, value), do: Secrets.set(key, value)

  @spec delete_secret(String.t()) :: :ok
  def delete_secret(key), do: Secrets.delete(key)

  @spec has_secret?(String.t()) :: boolean()
  def has_secret?(key), do: Secrets.has_key?(key)

  @spec get_node_id() :: String.t() | nil
  def get_node_id, do: get_config("node_id")

  @spec set_node_id(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_node_id(value), do: set_config("node_id", value)

  @spec get_admin_urls() :: [String.t()]
  def get_admin_urls do
    "admin_urls" |> get_config() |> ConfigValueCodec.decode_string_list()
  end

  @spec set_admin_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_admin_urls(urls) when is_list(urls) do
    set_config("admin_urls", ConfigValueCodec.encode_string_list(urls))
  end

  @spec get_vpn_enrollment_key() :: String.t() | nil
  def get_vpn_enrollment_key, do: get_config("vpn_enrollment_key")

  @spec set_vpn_enrollment_key(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_vpn_enrollment_key(value), do: set_config("vpn_enrollment_key", value)

  @spec get_enrollment_key_id() :: String.t() | nil
  def get_enrollment_key_id, do: get_config("enrollment_key_id")

  @spec set_enrollment_key_id(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_enrollment_key_id(value), do: set_config("enrollment_key_id", value)

  @spec get_last_check_self_update_at() :: DateTime.t() | nil
  def get_last_check_self_update_at do
    "last_check_self_update_at" |> get_config() |> ConfigValueCodec.decode_datetime()
  end

  @spec set_last_check_self_update_at(DateTime.t()) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_last_check_self_update_at(%DateTime{} = datetime) do
    iso_string = ConfigValueCodec.encode_datetime(datetime)
    set_config("last_check_self_update_at", iso_string)
  end

  @spec get_admin_fallback_urls() :: [String.t()]
  def get_admin_fallback_urls do
    "admin_fallback_urls" |> get_config() |> ConfigValueCodec.decode_string_list()
  end

  @spec set_admin_fallback_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def set_admin_fallback_urls(urls) when is_list(urls) do
    set_config("admin_fallback_urls", ConfigValueCodec.encode_string_list(urls))
  end

  @spec merge_admin_fallback_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def merge_admin_fallback_urls(urls),
    do: set_admin_fallback_urls(ConfigValueCodec.prepend_new_strings(urls, get_admin_fallback_urls()))

  @spec get_core_derp_map_urls() :: [String.t()]
  def get_core_derp_map_urls do
    "core_derp_map_urls" |> get_config() |> ConfigValueCodec.decode_string_list()
  end

  @spec merge_core_derp_map_urls([String.t()]) ::
          {:ok, Setting.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def merge_core_derp_map_urls(urls) do
    merged = ConfigValueCodec.prepend_new_strings(urls, get_core_derp_map_urls())
    set_config("core_derp_map_urls", ConfigValueCodec.encode_string_list(merged))
  end

  @spec get_api_token() :: String.t() | nil
  def get_api_token, do: get_config("api_token")

  @spec set_api_token(String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set_api_token(value), do: set_config("api_token", value)

  @spec get_proxy_password() :: String.t() | nil
  def get_proxy_password, do: get_secret("proxy_password")

  @spec set_proxy_password(String.t()) :: :ok
  def set_proxy_password(value), do: set_secret("proxy_password", value)
end
