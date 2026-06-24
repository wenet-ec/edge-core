# edge_admin/lib/edge_admin/events/broker/adapters/kafka.ex
defmodule EdgeAdmin.Events.Broker.Adapters.Kafka do
  @moduledoc """
  Kafka-compatible adapter for the event broker (Redpanda recommended).

  Uses `:brod` (Erlang Kafka client) to produce messages.
  Manages a named brod client `:event_broker_kafka` started in the supervision tree.

  ## Topics

      edge-nodes-events           partition key: node_id (or enrollment_key_id for enrollment events)
      edge-commands-events        partition key: command_execution_id
      edge-self-updates-events    partition key: self_update_request_id
      edge-ssh-events             partition key: node_id (verifications partition by the node attempting auth)

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
  - `EVENT_BROKER_KAFKA_URLS` — comma-separated `host:port` list
  - `EVENT_BROKER_KAFKA_USERNAME` — SASL username (optional)
  - `EVENT_BROKER_KAFKA_PASSWORD` — SASL password (optional)
  - `EVENT_BROKER_KAFKA_SASL_MECHANISM` — `plain` (default), `scram_sha_256`, `scram_sha_512`
  """

  @behaviour EdgeAdmin.Events.Broker.Adapter

  use GenServer

  alias EdgeAdmin.Events.Broker.Adapter

  require Logger

  @client :event_broker_kafka

  @topics [
    "edge-nodes-events",
    "edge-commands-events",
    "edge-self-updates-events",
    "edge-ssh-events"
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
    payload = JSON.encode!(envelope)

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
    {:ok, %{}, {:continue, :start_client}}
  end

  @impl GenServer
  def handle_continue(:start_client, state), do: do_start_client(state)

  @impl GenServer
  def handle_info(:start_client, state), do: do_start_client(state)

  defp do_start_client(state) do
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

  defp topic_for("edge.node." <> _), do: "edge-nodes-events"
  defp topic_for("edge.enrollment_key." <> _), do: "edge-nodes-events"
  defp topic_for("edge.command_execution." <> _), do: "edge-commands-events"
  defp topic_for("edge.self_update_request." <> _), do: "edge-self-updates-events"
  defp topic_for("edge.ssh_username." <> _), do: "edge-ssh-events"

  # Partition key — Kafka uses it for two things: (1) co-locating events with
  # the same key onto the same partition (in-partition ordering is guaranteed,
  # cross-partition is not), and (2) hash-distributing across partitions for
  # parallel consumption. It is NOT a dedup key, NOT a uniqueness constraint —
  # purely routing.
  #
  # Choice rationale: pick whichever id consumers care about ordering by. For
  # executions we partition by `command_execution_id` so a single execution's
  # lifecycle (created → sent → completed/expired/cancelled → pruned) stays on
  # one partition. We do NOT partition by node_id (which would give per-node
  # command timelines but lose per-execution ordering) or command_id (which
  # would group fan-out under one partition and bottleneck large rollouts).
  #
  # Order of clauses matters since execution events also carry node_id —
  # command_execution_id must match first. enrollment_key events carry no
  # node_id; on `:invalid_key` even enrollment_key_id is null and we fall
  # through to the empty-string default.
  defp partition_key_for(%{"data" => %{"command_execution_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(%{"data" => %{"self_update_request_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(%{"data" => %{"enrollment_key_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(%{"data" => %{"node_id" => id}}) when is_binary(id), do: id
  defp partition_key_for(_), do: ""
end
