# edge_admin/lib/edge_admin/event_broker/adapters/nats.ex
defmodule EdgeAdmin.EventBroker.Adapters.Nats do
  @moduledoc """
  NATS adapter for the event broker. Supports two modes:

  - **Pub/sub** (default) — plain `Gnat.pub/3`, fire-and-forget. Messages are
    lost when no subscriber is connected.
  - **JetStream** — set `EVENT_BROKER_NATS_JETSTREAM=true`. Same pub call, but
    JetStream intercepts it and persists the message into a durable stream.
    On startup, the adapter auto-creates the three streams if absent.

  ## Subjects

      edge.node.<event>         → captured by EDGE_NODE_EVENTS stream (JetStream only)
      edge.execution.<event>    → captured by EDGE_EXECUTION_EVENTS stream (JetStream only)
      edge.self_update.<event>  → captured by EDGE_SELF_UPDATE_EVENTS stream (JetStream only)

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_nats,
        urls: ["nats://edge_event_broker:4222"],   # list — all used for failover/load balancing
        jetstream: false,   # set via EVENT_BROKER_NATS_JETSTREAM=true to enable durable log
        # Auth — mutually exclusive, first match wins:
        token: nil,         # shared token  (EVENT_BROKER_NATS_TOKEN)
        username: nil,      # username/password  (EVENT_BROKER_NATS_USERNAME / _PASSWORD)
        password: nil,
        nkey_seed: nil,     # NKey seed — standalone or paired with jwt  (EVENT_BROKER_NATS_NKEY_SEED)
        jwt: nil            # JWT credential — used alongside nkey_seed  (EVENT_BROKER_NATS_JWT)
  """

  @behaviour EdgeAdmin.EventBroker.Adapter

  use GenServer

  alias EdgeAdmin.EventBroker.Adapter
  alias Gnat.Jetstream.API.Stream, as: JsStream

  require Logger

  @conn :event_broker_nats

  @streams [
    %JsStream{name: "EDGE_NODE_EVENTS", subjects: ["edge.node.>"], storage: :file},
    %JsStream{name: "EDGE_EXECUTION_EVENTS", subjects: ["edge.execution.>"], storage: :file},
    %JsStream{name: "EDGE_SELF_UPDATE_EVENTS", subjects: ["edge.self_update.>"], storage: :file}
  ]

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
    Gnat.server_info(@conn)
    :ok
  catch
    :exit, _ -> {:error, "not connected to NATS"}
  end

  @impl Adapter
  def publish(envelope) do
    payload = Jason.encode!(envelope)
    Gnat.pub(@conn, envelope["type"], payload)
  end

  # ---------------------------------------------------------------------------
  # GenServer — startup, JetStream stream provisioning
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    config = Application.get_env(:edge_admin, :event_broker_nats, [])

    if Keyword.get(config, :jetstream, false) do
      send(self(), :ensure_streams)
    end

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:ensure_streams, state) do
    if connection_ready?() do
      case ensure_streams() do
        :ok ->
          {:noreply, state}

        {:error, reason} ->
          Logger.warning("[EventBroker.Nats] Stream setup failed: #{inspect(reason)} — will retry in 10s")
          Process.send_after(self(), :ensure_streams, 10_000)
          {:noreply, state}
      end
    else
      Process.send_after(self(), :ensure_streams, 2_000)
      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp connection_ready?, do: healthy?() == :ok

  defp ensure_streams do
    Enum.reduce_while(@streams, :ok, fn stream, :ok ->
      case create_or_skip(stream) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp create_or_skip(stream) do
    case JsStream.create(@conn, stream) do
      {:ok, _info} ->
        Logger.info("[EventBroker.Nats] Stream created: #{stream.name}")
        :ok

      {:error, %{"code" => 400}} ->
        # Stream already exists — this is fine
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
