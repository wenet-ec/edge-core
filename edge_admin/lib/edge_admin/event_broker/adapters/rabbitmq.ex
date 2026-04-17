# edge_admin/lib/edge_admin/event_broker/adapters/rabbitmq.ex
defmodule EdgeAdmin.EventBroker.Adapters.RabbitMQ do
  @moduledoc """
  RabbitMQ adapter for the event broker.

  Uses a single topic exchange `edge.events`. Routing key = `envelope["type"]`
  (e.g. `edge.node.registered`). Consumers subscribe to the exchange with any
  binding key — `edge.node.*`, `edge.execution.#`, `edge.#`, etc.

  The exchange is declared durable on startup. Consumer queue durability is the
  consumer's choice — Core publishes and forgets.

  ## Auth

  Embed credentials directly in the URL: `amqp://user:pass@host:port/vhost`.
  The amqp library parses them natively — no separate env vars needed.

  ## TLS

  Set `EVENT_BROKER_RABBITMQ_SSL=true` to enable TLS (`amqps://`). The amqp
  library uses the OTP `:ssl` application; no client certs required for standard
  managed brokers that present a trusted CA-signed certificate.

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_rabbitmq,
        url: "amqp://guest:guest@localhost:5672",
        ssl: false    # set true for TLS (amqps://)

  Controlled by env vars:
  - `EVENT_BROKER_URLS` — AMQP URL, e.g. `amqp://host:5672` or `amqp://user:pass@host:5672/vhost`
                          (only the first URL is used — RabbitMQ clustering is handled by the broker)
  - `EVENT_BROKER_RABBITMQ_SSL=true` — enable TLS (default: false)
  """

  @behaviour EdgeAdmin.EventBroker.Adapter

  use GenServer

  alias EdgeAdmin.EventBroker.Adapter

  require Logger

  @exchange "edge.events"

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
    _ -> {:error, "RabbitMQ adapter not started"}
  end

  @impl Adapter
  def publish(envelope) do
    GenServer.call(__MODULE__, {:publish, envelope})
  rescue
    _ -> {:error, "RabbitMQ adapter not started"}
  end

  # ---------------------------------------------------------------------------
  # GenServer — connection + channel management
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    send(self(), :connect)
    {:ok, %{conn: nil, channel: nil}}
  end

  @impl GenServer
  def handle_call(:healthy?, _from, %{channel: nil} = state) do
    {:reply, {:error, "not connected to RabbitMQ"}, state}
  end

  def handle_call(:healthy?, _from, %{channel: channel} = state) do
    if Process.alive?(channel.pid) do
      {:reply, :ok, state}
    else
      {:reply, {:error, "RabbitMQ channel is down"}, state}
    end
  end

  def handle_call({:publish, _envelope}, _from, %{channel: nil} = state) do
    {:reply, {:error, "not connected to RabbitMQ"}, state}
  end

  def handle_call({:publish, envelope}, _from, %{channel: channel} = state) do
    routing_key = envelope["type"]
    payload = Jason.encode!(envelope)

    result =
      AMQP.Basic.publish(channel, @exchange, routing_key, payload,
        content_type: "application/json",
        persistent: true
      )

    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:connect, state) do
    config = Application.get_env(:edge_admin, :event_broker_rabbitmq, [])
    url = Keyword.get(config, :url, "amqp://localhost:5672")
    ssl = Keyword.get(config, :ssl, false)

    conn_opts = if ssl, do: [ssl_options: [verify: :verify_peer, customize_hostname_check: []]], else: []

    case AMQP.Connection.open(url, conn_opts) do
      {:ok, conn} ->
        Process.monitor(conn.pid)

        case AMQP.Channel.open(conn) do
          {:ok, channel} ->
            Process.monitor(channel.pid)
            :ok = AMQP.Exchange.declare(channel, @exchange, :topic, durable: true)
            Logger.info("[EventBroker.RabbitMQ] Connected, exchange declared: #{@exchange}")
            {:noreply, %{conn: conn, channel: channel}}

          {:error, reason} ->
            Logger.warning("[EventBroker.RabbitMQ] Channel open failed: #{inspect(reason)} — will retry in 10s")
            AMQP.Connection.close(conn)
            Process.send_after(self(), :connect, 10_000)
            {:noreply, %{state | conn: nil, channel: nil}}
        end

      {:error, reason} ->
        Logger.warning("[EventBroker.RabbitMQ] Connection failed: #{inspect(reason)} — will retry in 10s")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, %{state | conn: nil, channel: nil}}
    end
  end

  # Connection or channel went down — reconnect
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning("[EventBroker.RabbitMQ] Connection lost (#{inspect(reason)}) — reconnecting in 5s")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | conn: nil, channel: nil}}
  end
end
