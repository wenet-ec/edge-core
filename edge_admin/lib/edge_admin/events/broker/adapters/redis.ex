# edge_admin/lib/edge_admin/events/broker/adapters/redis.ex
defmodule EdgeAdmin.Events.Broker.Adapters.Redis do
  @moduledoc """
  Redis adapter for the event broker.

  Publishes events through Redis Pub/Sub using the event type as the channel.
  Delivery is transient: Redis Pub/Sub provides no replay or retention.

  Standalone, Sentinel, and Cluster connection modes are selected by
  deployment configuration. Authentication and TLS apply to every connection.
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
