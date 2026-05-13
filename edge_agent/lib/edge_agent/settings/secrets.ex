# edge_agent/lib/edge_agent/settings/secrets.ex
defmodule EdgeAgent.Settings.Secrets do
  @moduledoc """
  In-memory engine for session-scoped secrets.

  Values live in `:persistent_term` for the lifetime of the BEAM. Written once
  by bootstrap after (re)registration with admin; reread on every hot-path
  call (auth plugs, proxy credential checks). The agent generates a fresh
  set on each boot — "rotation" happens at the process boundary, so there is
  no in-process invalidation API.

  Direct callers should be limited to `EdgeAgent.Settings` (the facade) and
  tests. Other modules go through the facade.

  ## Why `:persistent_term`

  Reads are a single VM term load — faster than ETS and without a copy. The
  global GC sweep on write is a non-issue here because writes happen at most
  a handful of times across the BEAM's lifetime (one per successful bootstrap
  attempt). See `Bootstrap` for the write call site.
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
