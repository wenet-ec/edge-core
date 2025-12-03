# edge_agent/lib/edge_agent/settings.ex
defmodule EdgeAgent.Settings do
  @moduledoc """
  Simple key-value settings storage for agent configuration.

  Stores settings like:
  - node_id: The agent's node identifier
  - id_type: Type of ID (persistent or random)
  - api_token: Token for authenticating with admin API
  - proxy_password: Password for proxy authentication
  - admin_urls: JSON-encoded list of admin URLs
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Repo
  alias EdgeAgent.Settings.Setting

  @doc """
  Get a setting value by key.

  Returns the value if found, otherwise returns the default.
  """
  def get(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> default
    end
  end

  @doc """
  Set a setting value by key.

  Creates the setting if it doesn't exist, updates it if it does.
  """
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
  """
  def delete(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:ok, nil}
      setting -> Repo.delete(setting)
    end
  end

  @doc """
  Check if a setting key exists.
  """
  def has_key?(key) do
    Setting
    |> where([s], s.key == ^key)
    |> Repo.exists?()
  end

  @doc """
  Get all settings as a map.
  """
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
  def get_node_id, do: get("node_id")

  @doc """
  Set the node ID.
  """
  def set_node_id(value), do: set("node_id", value)

  @doc """
  Get the node ID type (persistent or random).
  """
  def get_id_type, do: get("id_type")

  @doc """
  Set the node ID type.
  """
  def set_id_type(value), do: set("id_type", value)

  @doc """
  Get the API token for admin authentication.
  """
  def get_api_token, do: get("api_token")

  @doc """
  Set the API token.
  """
  def set_api_token(value), do: set("api_token", value)

  @doc """
  Get the proxy password.
  """
  def get_proxy_password, do: get("proxy_password")

  @doc """
  Set the proxy password.
  """
  def set_proxy_password(value), do: set("proxy_password", value)

  @doc """
  Get admin URLs as a list.

  Returns a list of admin URL strings, or empty list if not set.
  The URLs are stored as a JSON-encoded string.
  """
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
  def set_admin_urls(urls) when is_list(urls) do
    case Jason.encode(urls) do
      {:ok, json} -> set("admin_urls", json)
      {:error, _} -> {:error, "Failed to encode admin URLs"}
    end
  end
end
