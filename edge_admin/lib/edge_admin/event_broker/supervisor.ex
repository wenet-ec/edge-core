# edge_admin/lib/edge_admin/event_broker/supervisor.ex
defmodule EdgeAdmin.EventBroker.Supervisor do
  @moduledoc """
  Starts the event broker connection and adapter process.

  Only added to the supervision tree when `EVENT_BROKER_ENABLED=true`.
  If disabled, this supervisor is never started and the app is unaffected.

  ## Children (NATS adapter)

    1. `Gnat.ConnectionSupervisor` — maintains a named NATS connection with
       automatic reconnect.
    2. `EdgeAdmin.EventBroker.Adapters.Nats` — GenServer that optionally ensures
       JetStream streams exist on startup (when `EVENT_BROKER_NATS_JETSTREAM=true`).

  ## Children (Kafka adapter)

    1. `EdgeAdmin.EventBroker.Adapters.Kafka` — GenServer that starts the
       `:brod` client and per-topic producers.

  ## Children (RabbitMQ adapter)

    1. `EdgeAdmin.EventBroker.Adapters.RabbitMQ` — GenServer that opens an
       AMQP connection + channel, declares the topic exchange, and monitors
       the connection for auto-reconnect.
  """

  use Supervisor

  require Logger

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl Supervisor
  def init([]) do
    adapter = Application.get_env(:edge_admin, :event_broker_adapter)
    children = build_children(adapter)
    Logger.info("[EventBroker] Starting with adapter: #{inspect(adapter)}")
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_children(:nats) do
    config = Application.get_env(:edge_admin, :event_broker_nats, [])
    urls = Keyword.get(config, :urls, ["nats://localhost:4222"])

    auth = nats_auth(config)

    connection_settings =
      Enum.map(urls, fn url ->
        uri = URI.parse(url)
        base = %{host: to_charlist(uri.host || "localhost"), port: uri.port || 4222}
        Map.merge(base, auth)
      end)

    nats_supervisor_settings = %{
      name: :event_broker_nats,
      backoff_period: 5_000,
      connection_settings: connection_settings
    }

    [
      {Gnat.ConnectionSupervisor, nats_supervisor_settings},
      EdgeAdmin.EventBroker.Adapters.Nats
    ]
  end

  defp build_children(:kafka) do
    [EdgeAdmin.EventBroker.Adapters.Kafka]
  end

  defp build_children(:rabbitmq) do
    [EdgeAdmin.EventBroker.Adapters.RabbitMQ]
  end

  # Auth precedence: token → username/password → nkey+jwt → nkey only → none
  defp nats_auth(config) do
    token = present(Keyword.get(config, :token))
    username = present(Keyword.get(config, :username))
    password = present(Keyword.get(config, :password))
    nkey_seed = present(Keyword.get(config, :nkey_seed))
    jwt = present(Keyword.get(config, :jwt))

    cond do
      token -> %{token: token}
      username && password -> %{username: username, password: password}
      nkey_seed && jwt -> %{nkey_seed: nkey_seed, jwt: jwt}
      nkey_seed -> %{nkey_seed: nkey_seed}
      true -> %{}
    end
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil
end
