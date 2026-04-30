# edge_admin/lib/edge_admin/event_broker/adapters/mqtt.ex
defmodule EdgeAdmin.EventBroker.Adapters.Mqtt do
  @moduledoc """
  MQTT adapter for the event broker.

  Publishes events to an MQTT broker via the `emqtt` Erlang client. Topic =
  event type with `.` rewritten to `/` (e.g. `edge/node/registered`) so MQTT
  segment-wildcards work naturally — subscribers can use `edge/#`,
  `edge/node/+`, `edge/execution/completed`, etc.

  Pub/sub semantics — durability, retention, and replay are the broker's
  concern. MQTT QoS controls only the publisher↔broker↔subscriber delivery
  handshake, not whether the broker stores history. Subscribers wanting
  offline queueing connect with `clean_session=false` on their own.

  ## QoS

  Globally configurable via `EVENT_BROKER_MQTT_QOS=0|1|2`, default 1.

  - QoS 0 — fire and forget, no broker ACK
  - QoS 1 — at-least-once, broker ACKs receipt (default)
  - QoS 2 — exactly-once delivery handshake (slowest)

  Consumers should dedup on envelope `id` regardless — multi-admin setups
  already produce duplicate node.status_changed events from independent health
  checkers.

  ## Auth (mutually exclusive)

  - `EVENT_BROKER_MQTT_JWT` — JWT bearer token, sent in the CONNECT password
    field. Brokers configured for JWT auth (EMQX, HiveMQ, etc.) validate it
    from there.
  - `EVENT_BROKER_MQTT_USERNAME` + `EVENT_BROKER_MQTT_PASSWORD` — plain
    credentials.
  - Neither — anonymous (matches the bundled broker's allow-all default).

  JWT takes precedence over username/password if both are set.

  ## TLS

  - `EVENT_BROKER_MQTT_SSL=true` — enable TLS for the connection.
  - `EVENT_BROKER_MQTT_CACERT_FILE` — custom CA bundle / pinning.
  - `EVENT_BROKER_MQTT_CLIENT_CERT_FILE` + `EVENT_BROKER_MQTT_CLIENT_KEY_FILE`
    — mTLS (client auth via certificate). Requires SSL=true.

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_mqtt,
        host: "edge_event_broker_mqtt",
        port: 1883,
        qos: 1,
        username: nil,
        password: nil,
        jwt: nil,
        ssl: false,
        cacert_file: nil,
        client_cert_file: nil,
        client_key_file: nil,
        client_id_prefix: "edge_admin"
  """

  @behaviour EdgeAdmin.EventBroker.Adapter

  use GenServer

  alias EdgeAdmin.EventBroker.Adapter

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
    _ -> {:error, "MQTT adapter not started"}
  end

  @impl Adapter
  def publish(envelope) do
    GenServer.call(__MODULE__, {:publish, envelope})
  rescue
    _ -> {:error, "MQTT adapter not started"}
  end

  # ---------------------------------------------------------------------------
  # GenServer — connection management
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    Process.flag(:trap_exit, true)
    send(self(), :connect)
    {:ok, %{client: nil}}
  end

  @impl GenServer
  def handle_call(:healthy?, _from, %{client: nil} = state) do
    {:reply, {:error, "not connected to MQTT broker"}, state}
  end

  def handle_call(:healthy?, _from, %{client: client} = state) do
    if Process.alive?(client) do
      {:reply, :ok, state}
    else
      {:reply, {:error, "MQTT client process is dead"}, state}
    end
  end

  def handle_call({:publish, _envelope}, _from, %{client: nil} = state) do
    {:reply, {:error, "not connected to MQTT broker"}, state}
  end

  def handle_call({:publish, envelope}, _from, %{client: client} = state) do
    config = Application.get_env(:edge_admin, :event_broker_mqtt, [])
    qos = Keyword.get(config, :qos, 1)
    topic = topic_for(envelope["type"])
    payload = Jason.encode!(envelope)

    case :emqtt.publish(client, topic, payload, qos) do
      :ok -> {:reply, :ok, state}
      {:ok, _packet_id} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  @impl GenServer
  def handle_info(:connect, _state) do
    config = Application.get_env(:edge_admin, :event_broker_mqtt, [])
    opts = build_emqtt_opts(config)

    with {:ok, client} <- :emqtt.start_link(opts),
         {:ok, _props} <- :emqtt.connect(client) do
      Process.monitor(client)
      Logger.info("[EventBroker.Mqtt] Connected to #{config[:host]}:#{config[:port]}")
      {:noreply, %{client: client}}
    else
      {:error, reason} ->
        Logger.warning("[EventBroker.Mqtt] Connection failed: #{inspect(reason)} — will retry in 10s")
        Process.send_after(self(), :connect, 10_000)
        {:noreply, %{client: nil}}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, _state) do
    Logger.warning("[EventBroker.Mqtt] Client process died (#{inspect(reason)}) — reconnecting in 5s")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{client: nil}}
  end

  def handle_info({:disconnected, reason_code, _props}, state) do
    Logger.warning("[EventBroker.Mqtt] Disconnected (reason_code=#{inspect(reason_code)})")
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, _state) do
    Logger.warning("[EventBroker.Mqtt] Linked process exited: #{inspect(reason)}")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{client: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # CloudEvents type uses dot-separated hierarchy (`edge.node.registered`).
  # MQTT segment wildcards (`+`, `#`) work on `/` — translate so subscribers
  # can use `edge/#`, `edge/node/+`, etc.
  defp topic_for(event_type), do: String.replace(event_type, ".", "/")

  defp build_emqtt_opts(config) do
    base = [
      host: to_charlist(Keyword.fetch!(config, :host)),
      port: Keyword.fetch!(config, :port),
      clientid: client_id(config),
      clean_start: true,
      proto_ver: :v5,
      keepalive: 60,
      reconnect: 0
    ]

    base
    |> add_auth(config)
    |> add_tls(config)
  end

  # JWT > username/password > anonymous. JWT is sent in the CONNECT password
  # slot — the username is set to "jwt" as a placeholder; brokers configured
  # for JWT auth ignore it and validate from the password.
  defp add_auth(opts, config) do
    jwt = present(config[:jwt])
    username = present(config[:username])
    password = present(config[:password])

    cond do
      jwt ->
        opts
        |> Keyword.put(:username, ~c"jwt")
        |> Keyword.put(:password, to_charlist(jwt))

      username && password ->
        opts
        |> Keyword.put(:username, to_charlist(username))
        |> Keyword.put(:password, to_charlist(password))

      true ->
        opts
    end
  end

  defp add_tls(opts, config) do
    if Keyword.get(config, :ssl, false) do
      ssl_opts = build_ssl_opts(config)
      opts |> Keyword.put(:ssl, true) |> Keyword.put(:ssl_opts, ssl_opts)
    else
      opts
    end
  end

  defp build_ssl_opts(config) do
    cacert = present(config[:cacert_file])
    client_cert = present(config[:client_cert_file])
    client_key = present(config[:client_key_file])

    if (client_cert && !client_key) || (!client_cert && client_key) do
      raise "EVENT_BROKER_MQTT_CLIENT_CERT_FILE and EVENT_BROKER_MQTT_CLIENT_KEY_FILE must be set together"
    end

    base = [verify: :verify_peer, depth: 4]

    base
    |> maybe_put_file(:cacertfile, cacert)
    |> maybe_put_file(:certfile, client_cert)
    |> maybe_put_file(:keyfile, client_key)
  end

  defp maybe_put_file(opts, _key, nil), do: opts
  defp maybe_put_file(opts, key, path), do: Keyword.put(opts, key, to_charlist(path))

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: value

  # Unique client ID per admin instance — MQTT brokers disconnect prior
  # sessions on duplicate client IDs, so uniqueness matters when multiple
  # admins share a broker.
  defp client_id(config) do
    prefix = Keyword.get(config, :client_id_prefix, "edge_admin")
    suffix = [:positive] |> :erlang.unique_integer() |> Integer.to_string()
    "#{prefix}-#{node()}-#{suffix}"
  end
end
