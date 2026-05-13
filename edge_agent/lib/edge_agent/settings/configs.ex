# edge_agent/lib/edge_agent/settings/configs.ex
defmodule EdgeAgent.Settings.Configs do
  @moduledoc """
  SQLite-backed engine for durable configuration values.

  Values written here survive process restarts. Used for identity and discovery
  state that the agent reloads on boot (node_id, admin_urls, enrollment_verified,
  etc.). Secrets do not belong here — see `EdgeAgent.Settings.Secrets`.

  Direct callers should be limited to `EdgeAgent.Settings` (the facade) and
  tests. Other modules go through the facade.
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Repo
  alias EdgeAgent.Settings.Schemas.Setting

  @spec get(String.t()) :: String.t() | nil
  @spec get(String.t(), default) :: String.t() | default when default: any()
  def get(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> default
    end
  end

  @spec set(String.t(), String.t()) :: {:ok, Setting.t()} | {:error, Ecto.Changeset.t()}
  def set(key, value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now(:second)]],
      conflict_target: :key
    )
  end

  @spec delete(String.t()) :: {:ok, Setting.t() | nil} | {:error, Ecto.Changeset.t()}
  def delete(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:ok, nil}
      setting -> Repo.delete(setting)
    end
  end

  @spec has_key?(String.t()) :: boolean()
  def has_key?(key) do
    Setting
    |> where([s], s.key == ^key)
    |> Repo.exists?()
  end

  @spec all() :: %{String.t() => String.t()}
  def all do
    Setting
    |> Repo.all()
    |> Map.new(fn %Setting{key: key, value: value} -> {key, value} end)
  end
end
