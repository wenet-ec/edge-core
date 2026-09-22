# edge_admin/lib/edge_admin/events/broker/adapters/nats.ex
defmodule EdgeAdmin.Events.Broker.Adapters.Nats do
  @moduledoc """
  NATS adapter for the event broker.

  Plain pub/sub is fire-and-forget. When JetStream is enabled, the adapter
  ensures its durable streams exist and publishes through the same subjects.
  Connection endpoints and authentication are supplied through deployment
  configuration.
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter
  alias Gnat.Jetstream.API.Stream, as: JsStream

  require Logger

  @conn :event_broker_nats

  @streams [
    %JsStream{
      name: "EDGE_NODES_EVENTS",
      subjects: ["edge.node.>", "edge.enrollment_key.>"],
      storage: :file
    },
    %JsStream{name: "EDGE_COMMANDS_EVENTS", subjects: ["edge.command_execution.>"], storage: :file},
    %JsStream{name: "EDGE_SELF_UPDATES_EVENTS", subjects: ["edge.self_update_request.>"], storage: :file},
    %JsStream{name: "EDGE_SSH_EVENTS", subjects: ["edge.ssh_username.>"], storage: :file},
    %JsStream{name: "EDGE_CORE_EVENTS", subjects: ["edge.core.>"], storage: :file}
  ]

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

  @doc "Returns the `Gnat.ConnectionSupervisor` child spec, built from application config."
  def connection_supervisor_spec do
    config = Application.get_env(:edge_admin, :event_broker_nats, [])
    urls = Keyword.fetch!(config, :urls)
    auth = build_auth(config)

    connection_settings =
      Enum.map(urls, fn url ->
        uri = URI.parse(url)
        base = %{host: to_charlist(uri.host), port: uri.port || 4222}
        base = Map.put(base, :name, Keyword.fetch!(config, :name))
        Map.merge(base, auth)
      end)

    {Gnat.ConnectionSupervisor,
     %{
       name: @conn,
       backoff_period: 5_000,
       connection_settings: connection_settings
     }}
  end

  @impl Adapter
  def healthy? do
    Gnat.server_info(@conn)
    :ok
  catch
    :exit, _ -> {:error, "not connected to NATS"}
  end

  @impl Adapter
  def publish(envelope) do
    payload = JSON.encode!(envelope)
    Gnat.pub(@conn, envelope["type"], payload)
  end

  @impl GenServer
  def init([]) do
    config = Application.get_env(:edge_admin, :event_broker_nats, [])

    if Keyword.get(config, :jetstream, false) do
      {:ok, %{}, {:continue, :ensure_streams}}
    else
      {:ok, %{}}
    end
  end

  @impl GenServer
  def handle_continue(:ensure_streams, state), do: do_ensure_streams(state)

  @impl GenServer
  def handle_info(:ensure_streams, state), do: do_ensure_streams(state)

  defp do_ensure_streams(state) do
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

  # Auth precedence: token → username/password → nkey+jwt → nkey only → none
  defp build_auth(config) do
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
