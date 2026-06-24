# edge_admin/lib/edge_admin/events/broker/adapters/redis.ex
defmodule EdgeAdmin.Events.Broker.Adapters.Redis do
  @moduledoc """
  Redis adapter for the event broker.

  Publishes events via Redis Pub/Sub using `PUBLISH`. Channel = event type
  (e.g. `edge.node.registered`). Fire-and-forget — no durability or replay.
  Subscribers use `SUBSCRIBE` or `PSUBSCRIBE edge.*` for wildcard matching.

  Compatible with Redis 2.0+ (Aug 2010, when Pub/Sub was introduced) and any
  wire-compatible server (Valkey, KeyDB, Dragonfly). The adapter uses only
  `PING` and `PUBLISH` over RESP2 — no version-gated commands. ACL-style
  URL usernames (`redis://user:pass@host`) and native TLS require Redis 6.0+
  (Apr 2020); password-only URLs (`redis://:pass@host`) work against any
  version.

  ## Auth

  Embed credentials in the URL: `redis://:password@host:port` or
  `redis://username:password@host:port` (Redis 6+ ACL). No separate env vars
  are needed — Redix parses the URL directly.

  ## TLS

  Set `EVENT_BROKER_REDIS_SSL=true` to enable TLS. Use `rediss://` URLs for
  external/hosted brokers (Redis Cloud, Upstash, etc.).

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_redis,
        url: "redis://host:6379",
        ssl: false

  Controlled by env vars:
  - `EVENT_BROKER_REDIS_URL` — Redis URL, e.g. `redis://host:6379` or `rediss://host:6380`.
                              Single endpoint — Redis Pub/Sub is single-node.
  - `EVENT_BROKER_REDIS_SSL=true` — enable TLS (default: false)
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter

  require Logger

  # ---------------------------------------------------------------------------
  # Supervision
  # ---------------------------------------------------------------------------

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Adapter callbacks
  # ---------------------------------------------------------------------------

  @impl Adapter
  def healthy? do
    case GenServer.call(__MODULE__, :healthy?) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, "Redis adapter not started"}
  end

  @impl Adapter
  def publish(envelope) do
    GenServer.call(__MODULE__, {:publish, envelope})
  rescue
    _ -> {:error, "Redis adapter not started"}
  end

  # ---------------------------------------------------------------------------
  # GenServer — connection management
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    {:ok, %{conn: nil}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state), do: do_connect(state)

  @impl GenServer
  def handle_call(:healthy?, _from, %{conn: nil} = state) do
    {:reply, {:error, "not connected to Redis"}, state}
  end

  def handle_call(:healthy?, _from, %{conn: conn} = state) do
    case Redix.command(conn, ["PING"]) do
      {:ok, "PONG"} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  def handle_call({:publish, _envelope}, _from, %{conn: nil} = state) do
    {:reply, {:error, "not connected to Redis"}, state}
  end

  def handle_call({:publish, envelope}, _from, %{conn: conn} = state) do
    channel = envelope["type"]
    payload = Jason.encode!(envelope)

    case Redix.command(conn, ["PUBLISH", channel, payload]) do
      {:ok, _subscribers} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  @impl GenServer
  def handle_info(:connect, state), do: do_connect(state)

  # Connection went down — reconnect
  def handle_info({:DOWN, _ref, :process, _pid, reason}, _state) do
    Logger.warning("[EventBroker.Redis] Connection lost (#{inspect(reason)}) — reconnecting in 5s")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{conn: nil}}
  end

  defp do_connect(_state) do
    config = Application.get_env(:edge_admin, :event_broker_redis, [])
    url = Keyword.fetch!(config, :url)
    ssl = Keyword.get(config, :ssl, false)

    opts = if ssl, do: [ssl: true], else: []

    case Redix.start_link(url, opts) do
      {:ok, conn} ->
        Process.monitor(conn)
        Logger.info("[EventBroker.Redis] Connected to #{url}")
        {:noreply, %{conn: conn}}

      {:error, reason} ->
        Logger.warning("[EventBroker.Redis] Connection failed: #{inspect(reason)} — will retry in 10s")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, %{conn: nil}}
    end
  end
end
