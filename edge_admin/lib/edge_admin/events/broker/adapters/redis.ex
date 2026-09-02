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
  `redis://username:password@host:port` (Redis 6+ ACL) in standalone mode.
  Sentinel mode uses `EVENT_BROKER_REDIS_USERNAME` and
  `EVENT_BROKER_REDIS_PASSWORD` for the resolved primary, with the optional
  `EVENT_BROKER_REDIS_SENTINEL_PASSWORD` for Sentinel authentication.

  ## TLS

  Set `EVENT_BROKER_REDIS_SSL=true` to enable TLS. Use `rediss://` URLs for
  external/hosted brokers (Redis Cloud, Upstash, etc.).

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_redis,
        mode: :standalone,
        url: "redis://host:6379",
        ssl: false

      # Sentinel mode:
      config :edge_admin, :event_broker_redis,
        mode: :sentinel,
        sentinel: [
          sentinels: ["redis://sentinel-a:26379", "redis://sentinel-b:26379"],
          group: "mymaster"
        ],
        ssl: false,
        username: nil,
        password: nil

  Controlled by env vars:
  - `EVENT_BROKER_REDIS_MODE` — `standalone` (default) or `sentinel`.
  - `EVENT_BROKER_REDIS_URL` — standalone Redis URL, e.g. `redis://host:6379` or `rediss://host:6380`.
  - `EVENT_BROKER_REDIS_SENTINELS` — comma-separated Sentinel host:port endpoints.
  - `EVENT_BROKER_REDIS_SENTINEL_GROUP` — Sentinel primary group name.
  - `EVENT_BROKER_REDIS_USERNAME` / `EVENT_BROKER_REDIS_PASSWORD` — primary credentials in Sentinel mode.
  - `EVENT_BROKER_REDIS_SENTINEL_PASSWORD` — optional Sentinel authentication password.
  - `EVENT_BROKER_REDIS_SSL=true` — enable TLS (default: false)
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter

  require Logger

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
    payload = JSON.encode!(envelope)

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
    mode = Keyword.fetch!(config, :mode)
    ssl = Keyword.get(config, :ssl, false)

    result =
      case mode do
        :standalone ->
          opts = if ssl, do: [ssl: true], else: []
          Redix.start_link(Keyword.fetch!(config, :url), opts)

        :sentinel ->
          opts = [sentinel: Keyword.fetch!(config, :sentinel), ssl: ssl]
          opts = Keyword.put(opts, :username, Keyword.get(config, :username))
          opts = Keyword.put(opts, :password, Keyword.get(config, :password))
          Redix.start_link(opts)
      end

    case result do
      {:ok, conn} ->
        Process.monitor(conn)
        Logger.info("[EventBroker.Redis] Connected (mode=#{mode})")
        {:noreply, %{conn: conn}}

      {:error, reason} ->
        Logger.warning("[EventBroker.Redis] Connection failed: #{inspect(reason)} — will retry in 10s")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, %{conn: nil}}
    end
  end
end
