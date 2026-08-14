# edge_admin/test/edge_admin/events/broker/adapter_registry_test.exs
defmodule EdgeAdmin.Events.Broker.AdapterRegistryTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Broker.AdapterRegistry

  test "registry exposes each adapter exactly once" do
    assert AdapterRegistry.names() == [:nats, :kafka, :rabbitmq, :redis, :mqtt, :aws_sns, :google_pubsub]
    assert AdapterRegistry.names() == Enum.uniq(AdapterRegistry.names())

    assert AdapterRegistry.wire_strings() == [
             "nats",
             "kafka",
             "amqp091",
             "rabbitmq",
             "redis",
             "mqtt",
             "aws_sns",
             "google_pubsub"
           ]

    assert AdapterRegistry.wire_strings() == Enum.uniq(AdapterRegistry.wire_strings())
  end

  test "wire-format names resolve to their canonical adapter" do
    assert AdapterRegistry.name_for_wire("nats") == :nats
    assert AdapterRegistry.name_for_wire("amqp091") == :rabbitmq
    assert AdapterRegistry.name_for_wire("rabbitmq") == :rabbitmq
    assert AdapterRegistry.name_for_wire("unknown") == nil
  end

  test "canonical names resolve to adapter modules" do
    for name <- AdapterRegistry.names() do
      module = AdapterRegistry.module_for(name)
      assert Code.ensure_loaded?(module)
      assert function_exported?(module, :publish, 1)
      assert function_exported?(module, :healthy?, 0)
    end
  end
end
