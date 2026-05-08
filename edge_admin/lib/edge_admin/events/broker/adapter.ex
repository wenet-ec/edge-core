# edge_admin/lib/edge_admin/events/broker/adapter.ex
defmodule EdgeAdmin.Events.Broker.Adapter do
  @moduledoc """
  Behaviour that all event broker adapters must implement, plus the
  single source of truth for the supported adapter list.

  ## Behaviour

  An adapter receives a fully-built envelope map and is responsible
  for serialising and publishing it to the underlying broker.

  ## Adapter registry

  The `@adapters` list below is the canonical record of every supported
  adapter. Each entry colocates the internal atom name, the implementation
  module, and the wire-format string(s) that map to that adapter (multiple
  strings allow protocol aliases — e.g. `"amqp091"` and `"rabbitmq"` both
  resolve to `:rabbitmq`).

  Three things are derived from this registry:

    * `names/0` — every internal atom name, used by the broker dispatch.
    * `wire_strings/0` — every accepted `EVENT_BROKER_ADAPTER` value, used by
      `runtime.exs` for parsing and for the rejection error message.
    * `module_for/1`, `name_for_wire/1` — lookups used by `Broker` and
      `runtime.exs` respectively.

  Compile-time assertions reject duplicate names or wire strings.

  ## Adding a new adapter

    1. Implement the `Adapter` behaviour in `broker/adapters/your_adapter.ex`.
    2. Add an entry to `@adapters` below.
    3. Add a `build_children/1` clause in `broker/supervisor.ex` for the
       adapter's supervised processes (this stays per-adapter because the
       supervision shape is genuinely heterogeneous).
    4. Add the per-adapter env-var parsing block in `config/runtime.exs`.

  The dispatch in `Broker` and the rejection error in `runtime.exs` pick up
  the new adapter automatically.
  """

  @doc """
  Publishes a pre-built event envelope to the broker.

  The envelope is already serialisable — all values are strings, numbers,
  or nested maps. Adapters should JSON-encode and publish it.

  Returns `:ok` on success or `{:error, reason}` on failure.
  The caller (`EdgeAdmin.Events.Broker.publish_envelope/1`) logs the error;
  adapters do not need to.
  """
  @callback publish(envelope :: map()) :: :ok | {:error, term()}

  @doc """
  Returns `:ok` if the adapter has an active connection to the broker,
  or `{:error, reason}` if not connected or the broker is unreachable.
  """
  @callback healthy?() :: :ok | {:error, String.t()}

  # ---------------------------------------------------------------------------
  # Registry
  # ---------------------------------------------------------------------------

  @adapters [
    %{name: :nats, module: EdgeAdmin.Events.Broker.Adapters.Nats, wire_strings: ~w(nats)},
    %{name: :kafka, module: EdgeAdmin.Events.Broker.Adapters.Kafka, wire_strings: ~w(kafka)},
    %{
      name: :rabbitmq,
      module: EdgeAdmin.Events.Broker.Adapters.Rabbitmq,
      wire_strings: ~w(amqp091 rabbitmq)
    },
    %{name: :redis, module: EdgeAdmin.Events.Broker.Adapters.Redis, wire_strings: ~w(redis)},
    %{name: :mqtt, module: EdgeAdmin.Events.Broker.Adapters.Mqtt, wire_strings: ~w(mqtt)},
    %{
      name: :aws_sns,
      module: EdgeAdmin.Events.Broker.Adapters.AwsSns,
      wire_strings: ~w(aws_sns)
    },
    %{
      name: :google_pubsub,
      module: EdgeAdmin.Events.Broker.Adapters.GooglePubsub,
      wire_strings: ~w(google_pubsub)
    }
  ]

  # Compile-time invariants on the registry.
  @all_names Enum.map(@adapters, & &1.name)
  if length(@all_names) != length(Enum.uniq(@all_names)) do
    raise "EdgeAdmin.Events.Broker.Adapter: duplicate adapter name in @adapters"
  end

  @all_wire_strings Enum.flat_map(@adapters, & &1.wire_strings)
  if length(@all_wire_strings) != length(Enum.uniq(@all_wire_strings)) do
    raise "EdgeAdmin.Events.Broker.Adapter: duplicate wire string in @adapters"
  end

  @modules_by_name Map.new(@adapters, &{&1.name, &1.module})
  @names_by_wire_string for entry <- @adapters,
                            wire <- entry.wire_strings,
                            into: %{},
                            do: {wire, entry.name}

  @doc "All internal adapter names, in registry order."
  @spec names() :: [atom()]
  def names, do: @all_names

  @doc """
  All accepted wire-format strings for `EVENT_BROKER_ADAPTER`, in registry
  order. Includes aliases (e.g. both `"amqp091"` and `"rabbitmq"`).
  """
  @spec wire_strings() :: [String.t()]
  def wire_strings, do: @all_wire_strings

  @doc "Returns the adapter module implementing the given internal name."
  @spec module_for(atom()) :: module()
  def module_for(name) when is_atom(name), do: Map.fetch!(@modules_by_name, name)

  @doc """
  Resolves a wire-format string to its internal atom name. Returns `nil` if
  the string is not a known adapter — callers (e.g. `runtime.exs`) own the
  rejection error so they can include the env-var name in context.
  """
  @spec name_for_wire(String.t()) :: atom() | nil
  def name_for_wire(string) when is_binary(string), do: Map.get(@names_by_wire_string, string)
end
