# edge_admin/lib/edge_admin/events/broker/adapter_registry.ex
defmodule EdgeAdmin.Events.Broker.AdapterRegistry do
  @moduledoc """
  Registry of supported event broker adapters.

  The registry is the canonical record of every supported adapter. Each entry
  colocates the internal atom name, the implementation module, and the
  wire-format string values that map to that adapter. Multiple strings allow
  protocol aliases, for example `"amqp091"` and `"rabbitmq"` both resolve to
  `:rabbitmq`.
  """

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

  @all_names Enum.map(@adapters, & &1.name)
  if length(@all_names) != length(Enum.uniq(@all_names)) do
    raise "EdgeAdmin.Events.Broker.AdapterRegistry: duplicate adapter name in @adapters"
  end

  @all_wire_strings Enum.flat_map(@adapters, & &1.wire_strings)
  if length(@all_wire_strings) != length(Enum.uniq(@all_wire_strings)) do
    raise "EdgeAdmin.Events.Broker.AdapterRegistry: duplicate wire string in @adapters"
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
  order. Includes aliases.
  """
  @spec wire_strings() :: [String.t()]
  def wire_strings, do: @all_wire_strings

  @doc "Returns the adapter module implementing the given internal name."
  @spec module_for(atom()) :: module()
  def module_for(name) when is_atom(name), do: Map.fetch!(@modules_by_name, name)

  @doc """
  Resolves a wire-format string to its internal atom name.

  Returns `nil` if the string is not a known adapter. Callers own rejection
  errors so they can include surface-specific context such as env-var names.
  """
  @spec name_for_wire(String.t()) :: atom() | nil
  def name_for_wire(string) when is_binary(string), do: Map.get(@names_by_wire_string, string)
end
