# edge_admin/lib/edge_admin/events/broker/adapters/redis.ex
defmodule EdgeAdmin.Events.Broker.Adapters.Redis do
  @moduledoc """
  Redis adapter for the event broker.

  Publishes events via Redis Pub/Sub using `PUBLISH`. Channel = event type
  (e.g. `edge.node.registered`). Fire-and-forget — no durability or replay.
  Subscribers use `SUBSCRIBE` or `PSUBSCRIBE edge.*` for wildcard matching.

  Compatible with Redis 2.0+ (Aug 2010, when Pub/Sub was introduced) and any
  wire-compatible server (Valkey, KeyDB, Dragonfly). The adapter uses only
  `PING` and `PUBLISH` over RESP2 — no version-gated commands. ACL usernames
  and native TLS require Redis 6.0+ (Apr 2020).

  ## Auth

  All modes use `EVENT_BROKER_REDIS_USERNAME` and
  `EVENT_BROKER_REDIS_PASSWORD` for primary connections. Sentinel additionally
  accepts `EVENT_BROKER_REDIS_SENTINEL_PASSWORD` for Sentinel authentication.

  Cluster mode uses Redix's topology manager only for `PING` and `PUBLISH`.
  It deliberately does not expose Redix's unsupported Cluster subscription
  interface: consumers continue using ordinary Redis `SUBSCRIBE` or
  `PSUBSCRIBE` against the cluster.

  ## TLS

  Set `EVENT_BROKER_REDIS_SSL=true` to enable TLS for every connection.

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_redis,
        mode: :standalone,
        endpoint: {"redis", 6379},
        primary_auth: [ssl: false]

      # Sentinel mode:
      config :edge_admin, :event_broker_redis,
        mode: :sentinel,
        sentinel: [
          sentinels: [[host: "sentinel-a", port: 26379], [host: "sentinel-b", port: 26379]],
          group: "mymaster"
        ],
        primary_auth: [ssl: false]

      # Cluster mode:
      config :edge_admin, :event_broker_redis,
        mode: :cluster,
        nodes: [[host: "redis-a", port: 6379], [host: "redis-b", port: 6379]],
        primary_auth: [ssl: false]

  Controlled by env vars:
  - `EVENT_BROKER_REDIS_MODE` — `standalone` (default), `sentinel`, or `cluster`.
  - `EVENT_BROKER_REDIS_URLS` — comma-separated `host:port` endpoints. Standalone
    requires exactly one endpoint; Sentinel treats them as Sentinel endpoints;
    Cluster treats them as topology-discovery seeds.
  - `EVENT_BROKER_REDIS_SENTINEL_GROUP` — Sentinel primary group name.
  - `EVENT_BROKER_REDIS_USERNAME` / `EVENT_BROKER_REDIS_PASSWORD` — primary credentials in every mode.
  - `EVENT_BROKER_REDIS_SENTINEL_PASSWORD` — optional Sentinel authentication password.
  - `EVENT_BROKER_REDIS_SSL=true` — enable TLS (default: false)
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter

  require Logger

  @cluster_name __MODULE__.Cluster

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
    {:ok, %{conn: nil, mode: nil}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state), do: do_connect(state)

  @impl GenServer
  def handle_call(:healthy?, _from, %{conn: nil} = state) do
    {:reply, {:error, "not connected to Redis"}, state}
  end

  def handle_call(:healthy?, _from, %{conn: conn, mode: mode} = state) do
    case command(mode, conn, ["PING"]) do
      {:ok, "PONG"} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  def handle_call({:publish, _envelope}, _from, %{conn: nil} = state) do
    {:reply, {:error, "not connected to Redis"}, state}
  end

  def handle_call({:publish, envelope}, _from, %{conn: conn, mode: mode} = state) do
    channel = envelope["type"]
    payload = JSON.encode!(envelope)

    case command(mode, conn, ["PUBLISH", channel, payload]) do
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
    {:noreply, %{conn: nil, mode: nil}}
  end

  defp do_connect(_state) do
    config = Application.get_env(:edge_admin, :event_broker_redis, [])
    mode = Keyword.fetch!(config, :mode)
    primary_auth = Keyword.fetch!(config, :primary_auth)

    result =
      case mode do
        :standalone ->
          {host, port} = Keyword.fetch!(config, :endpoint)
          Redix.start_link([host: host, port: port] ++ primary_auth)

        :sentinel ->
          Redix.start_link([sentinel: Keyword.fetch!(config, :sentinel)] ++ primary_auth)

        :cluster ->
          opts = [name: @cluster_name, nodes: Keyword.fetch!(config, :nodes)] ++ primary_auth

          case Redix.Cluster.start_link(opts) do
            {:ok, pid} -> {:ok, pid, @cluster_name}
            {:error, _reason} = error -> error
          end
      end

    case result do
      {:ok, pid, conn} ->
        Process.monitor(pid)
        Logger.info("[EventBroker.Redis] Connected (mode=#{mode})")
        {:noreply, %{conn: conn, mode: mode}}

      {:ok, conn} ->
        Process.monitor(conn)
        Logger.info("[EventBroker.Redis] Connected (mode=#{mode})")
        {:noreply, %{conn: conn, mode: mode}}

      {:error, reason} ->
        Logger.warning("[EventBroker.Redis] Connection failed: #{inspect(reason)} — will retry in 10s")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, %{conn: nil, mode: nil}}
    end
  end

  defp command(:cluster, conn, redis_command), do: Redix.Cluster.command(conn, redis_command)
  defp command(_mode, conn, redis_command), do: Redix.command(conn, redis_command)
end
