# edge_admin/lib/edge_admin/event_broker/adapters/kafka.ex
defmodule EdgeAdmin.EventBroker.Adapters.Kafka do
  @moduledoc """
  Kafka-compatible adapter for the event broker (Redpanda recommended).

  Uses `:brod` (Erlang Kafka client) to produce messages.
  Manages a named brod client `:event_broker_kafka` started in the supervision tree.

  ## Topics

      edge-node-events                  partition key: node_id
      edge-command-execution-events     partition key: command_id
      edge-self-update-request-events   partition key: request_id

  ## Configuration (set in runtime.exs from env vars)

      config :edge_admin, :event_broker_kafka,
        brokers: [{"edge_event_broker_kafka", 9092}],
        client_config: [
          # Optional SASL — omit entirely if auth is disabled
          sasl: {:plain, "admin", "secret"}
          # or: sasl: {:scram_sha_256, "admin", "secret"}
          # or: sasl: {:scram_sha_512, "admin", "secret"}
        ]

  Controlled by env vars:
  - `EVENT_BROKER_URLS` — comma-separated `host:port` list
  - `EVENT_BROKER_KAFKA_USERNAME` — SASL username (optional)
  - `EVENT_BROKER_KAFKA_PASSWORD` — SASL password (optional)
  - `EVENT_BROKER_KAFKA_SASL_MECHANISM` — `plain` (default), `scram_sha_256`, `scram_sha_512`
  """

  @behaviour EdgeAdmin.EventBroker.Adapter

  use GenServer

  alias EdgeAdmin.EventBroker.Adapter

  require Logger

  @client :event_broker_kafka

  @topics [
    "edge-node-events",
    "edge-command-execution-events",
    "edge-self-update-request-events"
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
    case :brod_client.get_metadata(@client, :all) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Kafka broker unreachable: #{inspect(reason)}"}
    end
  rescue
    _ -> {:error, "Kafka client not started"}
  end

  @impl Adapter
  def publish(envelope) do
    topic = topic_for(envelope["type"])
    partition_key = partition_key_for(envelope)
    payload = Jason.encode!(envelope)

    case :brod.produce_sync(@client, topic, :hash, partition_key, payload) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer — startup, topic + producer initialisation
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init([]) do
    send(self(), :start_client)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:start_client, state) do
    config = Application.get_env(:edge_admin, :event_broker_kafka, [])
    brokers = Keyword.fetch!(config, :brokers)
    client_config = Keyword.get(config, :client_config, [])

    # Resolve broker hostnames to IPs before passing to brod. brod does its own
    # DNS lookup internally and crashes hard (erlang:exit) on failure with no
    # retry. Pre-resolving here lets us handle failures gracefully and retry,
    # and also means brod connects by IP and never needs to resolve again.
    case resolve_brokers(brokers) do
      {:ok, resolved_brokers} ->
        case :brod.start_client(resolved_brokers, @client, client_config) do
          :ok ->
            start_producers()
            {:noreply, state}

          {:error, {:already_started, _}} ->
            start_producers()
            {:noreply, state}

          {:error, reason} ->
            Logger.warning("[EventBroker.Kafka] Client start failed: #{inspect(reason)} — will retry in 10s")
            Process.send_after(self(), :start_client, 10_000)
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("[EventBroker.Kafka] Broker DNS resolution failed: #{inspect(reason)} — will retry in 10s")
        Process.send_after(self(), :start_client, 10_000)
        {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Resolve all broker hostnames to IP tuples before passing to brod.
  # Returns {:ok, [{ip_tuple, port}]} or {:error, reason} on first failure.
  defp resolve_brokers(brokers) do
    brokers
    |> Enum.reduce_while({:ok, []}, fn {host, port}, {:ok, acc} ->
      case :inet.getaddr(String.to_charlist(host), :inet) do
        {:ok, ip} -> {:cont, {:ok, [{ip, port} | acc]}}
        {:error, reason} -> {:halt, {:error, {host, reason}}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp start_producers do
    Enum.each(@topics, fn topic ->
      case :brod.start_producer(@client, topic, []) do
        :ok ->
          Logger.info("[EventBroker.Kafka] Producer started for topic: #{topic}")

        {:error, reason} ->
          Logger.warning("[EventBroker.Kafka] Producer start failed for #{topic}: #{inspect(reason)}")
      end
    end)
  end

  defp topic_for("edge.node." <> _), do: "edge-node-events"
  defp topic_for("edge.execution." <> _), do: "edge-command-execution-events"
  defp topic_for("edge.self_update." <> _), do: "edge-self-update-request-events"

  # Partition key — ensures ordering per entity, parallel across entities
  defp partition_key_for(%{"data" => %{"node_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(%{"data" => %{"command_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(%{"data" => %{"request_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(_), do: ""
end
