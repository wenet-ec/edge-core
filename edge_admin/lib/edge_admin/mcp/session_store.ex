# edge_admin/lib/edge_admin/mcp/session_store.ex
defmodule EdgeAdmin.Mcp.SessionStore do
  @moduledoc """
  In-memory ETS-based session store for the Anubis MCP server.

  Satisfies the `Anubis.Server.Session.Store` behaviour using ETS so that
  MCP sessions survive endpoint restarts within the same BEAM node. Sessions
  are not persisted across node restarts — this is acceptable because the
  admin is stateless and MCP clients reconnect automatically.

  Configured via:

      config :anubis_mcp, :session_store,
        adapter: EdgeAdmin.Mcp.SessionStore,
        ttl: 1_800_000

  TTL is in milliseconds (default 30 minutes).
  """

  @behaviour Anubis.Server.Session.Store

  use GenServer

  @table __MODULE__
  @default_ttl :timer.minutes(30)

  # --- GenServer ---

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    {:ok, %{ttl: ttl}}
  end

  @impl Anubis.Server.Session.Store
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Store callbacks ---

  @impl Anubis.Server.Session.Store
  def save(session_id, state, opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table, {session_id, state, expires_at})
    :ok
  end

  @impl Anubis.Server.Session.Store
  def load(session_id, _opts) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, session_id) do
      [{^session_id, state, expires_at}] when expires_at > now -> {:ok, state}
      [{^session_id, _state, _expired}] -> {:error, :expired}
      [] -> {:error, :not_found}
    end
  end

  @impl Anubis.Server.Session.Store
  def delete(session_id, _opts) do
    :ets.delete(@table, session_id)
    :ok
  end

  @impl Anubis.Server.Session.Store
  def list_active(_opts) do
    now = System.monotonic_time(:millisecond)

    ids =
      :ets.tab2list(@table)
      |> Enum.filter(fn {_id, _state, expires_at} -> expires_at > now end)
      |> Enum.map(fn {id, _state, _expires_at} -> id end)

    {:ok, ids}
  end

  @impl Anubis.Server.Session.Store
  def update_ttl(session_id, ttl_ms, _opts) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, session_id) do
      [{^session_id, state, _old_expires}] ->
        :ets.insert(@table, {session_id, state, now + ttl_ms})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl Anubis.Server.Session.Store
  def update(session_id, updates, _opts) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, state, expires_at}] ->
        :ets.insert(@table, {session_id, Map.merge(state, updates), expires_at})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl Anubis.Server.Session.Store
  def cleanup_expired(_opts) do
    now = System.monotonic_time(:millisecond)

    expired =
      :ets.tab2list(@table)
      |> Enum.filter(fn {_id, _state, expires_at} -> expires_at <= now end)

    Enum.each(expired, fn {id, _state, _expires_at} -> :ets.delete(@table, id) end)

    {:ok, length(expired)}
  end
end
