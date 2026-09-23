# edge_agent/lib/edge_agent/settings/secrets.ex
defmodule EdgeAgent.Settings.Secrets do
  @moduledoc """
  In-memory engine for session-scoped secrets.

  Values live in `:persistent_term` for the lifetime of the BEAM. They are
  repopulated by bootstrap after registration and read directly by hot paths.
  There is no in-process invalidation API beyond deleting a named value.

  Direct callers should be limited to `EdgeAgent.Settings` (the facade) and
  tests. Other modules go through the facade.

  Reads are direct VM term loads. This engine is reserved for values that are
  safe to keep only for the current BEAM lifetime.
  """

  @namespace __MODULE__

  @spec get(String.t()) :: String.t() | nil
  @spec get(String.t(), default) :: String.t() | default when default: any()
  def get(key, default \\ nil) when is_binary(key) do
    :persistent_term.get({@namespace, key}, default)
  end

  @spec set(String.t(), String.t()) :: :ok
  def set(key, value) when is_binary(key) and is_binary(value) do
    :persistent_term.put({@namespace, key}, value)
  end

  @spec delete(String.t()) :: :ok
  def delete(key) when is_binary(key) do
    _ = :persistent_term.erase({@namespace, key})
    :ok
  end

  @spec has_key?(String.t()) :: boolean()
  def has_key?(key) when is_binary(key) do
    case :persistent_term.get({@namespace, key}, :__missing__) do
      :__missing__ -> false
      _ -> true
    end
  end
end
