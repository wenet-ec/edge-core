# edge_admin/lib/edge_admin/event_broker/adapters/nats_js.ex
defmodule EdgeAdmin.EventBroker.Adapters.NatsJs do
  @moduledoc """
  NATS JetStream adapter for the event broker.

  Manages a supervised `Gnat.ConnectionSupervisor` named `:event_broker_nats`.
  On startup, ensures the three JetStream streams exist (creates them if absent,
  does nothing if they already exist).

  Publishing uses `Gnat.pub/3` into a JetStream-captured subject. JetStream
  intercepts the plain `pub` and persists it into the matching stream.

  ## Subjects

      edge.node.<event>         → captured by EDGE_NODE_EVENTS stream
      edge.execution.<event>    → captured by EDGE_EXECUTION_EVENTS stream
      edge.self_update.<event>  → captured by EDGE_SELF_UPDATE_EVENTS stream

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_nats,
        urls: ["nats://edge_event_broker:4222"],   # list — all used for failover/load balancing
        token: nil  # set via EVENT_BROKER_NATS_TOKEN if NATS auth is enabled
  """

  @behaviour EdgeAdmin.EventBroker.Adapter

  use GenServer

  alias EdgeAdmin.EventBroker.Adapter
  alias Gnat.Jetstream.API.Stream, as: JsStream

  require Logger

  @conn :event_broker_nats

  @streams [
    %JsStream{
      name: "EDGE_NODE_EVENTS",
      subjects: ["edge.node.>"],
      storage: :file,
      retention: :limits,
      max_age: 7 * 24 * 60 * 60 * 1_000_000_000
    },
    %JsStream{
      name: "EDGE_EXECUTION_EVENTS",
      subjects: ["edge.execution.>"],
      storage: :file,
      retention: :limits,
      max_age: 7 * 24 * 60 * 60 * 1_000_000_000
    },
    %JsStream{
      name: "EDGE_SELF_UPDATE_EVENTS",
      subjects: ["edge.self_update.>"],
      storage: :file,
      retention: :limits,
      max_age: 7 * 24 * 60 * 60 * 1_000_000_000
    }
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
  # Adapter callback
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
  # GenServer — startup, stream provisioning
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    send(self(), :ensure_streams)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:ensure_streams, state) do
    if connection_ready?() do
      case ensure_streams() do
        :ok ->
          {:noreply, state}

        {:error, reason} ->
          Logger.warning("[EventBroker.NatsJs] Stream setup failed: #{inspect(reason)} — will retry in 10s")
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
        Logger.info("[EventBroker.NatsJs] Stream created: #{stream.name}")
        :ok

      {:error, %{"code" => 400}} ->
        # Stream already exists — this is fine
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
