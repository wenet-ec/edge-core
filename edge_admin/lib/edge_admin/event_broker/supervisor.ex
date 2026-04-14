# edge_admin/lib/edge_admin/event_broker/supervisor.ex
defmodule EdgeAdmin.EventBroker.Supervisor do
  @moduledoc """
  Starts the event broker connection and adapter process.

  Only added to the supervision tree when `EVENT_BROKER_ENABLED=true`.
  If disabled, this supervisor is never started and the app is unaffected.

  ## Children (NATS JetStream adapter)

    1. `Gnat.ConnectionSupervisor` — maintains a named NATS connection with
       automatic reconnect.
    2. `EdgeAdmin.EventBroker.Adapters.NatsJs` — GenServer that ensures
       JetStream streams exist on startup.

  ## Children (Kafka adapter)

    1. `EdgeAdmin.EventBroker.Adapters.Kafka` — GenServer that starts the
       `:brod` client and per-topic producers.
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

  defp build_children(:nats_js) do
    config = Application.get_env(:edge_admin, :event_broker_nats, [])
    urls = Keyword.get(config, :urls, ["nats://localhost:4222"])
    token = Keyword.get(config, :token)

    connection_settings =
      Enum.map(urls, fn url ->
        uri = URI.parse(url)
        maybe_put_token(%{host: to_charlist(uri.host || "localhost"), port: uri.port || 4222}, token)
      end)

    nats_supervisor_settings = %{
      name: :event_broker_nats,
      backoff_period: 5_000,
      connection_settings: connection_settings
    }

    [
      {Gnat.ConnectionSupervisor, nats_supervisor_settings},
      EdgeAdmin.EventBroker.Adapters.NatsJs
    ]
  end

  defp build_children(:kafka) do
    [EdgeAdmin.EventBroker.Adapters.Kafka]
  end

  defp maybe_put_token(settings, token) when is_binary(token) and token != "", do: Map.put(settings, :token, token)

  defp maybe_put_token(settings, _), do: settings
end
