# edge_admin/test/edge_admin/events/broker/adapter_test.exs
defmodule EdgeAdmin.Events.Broker.AdapterTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Broker.Adapter

  test "registry exposes each adapter exactly once" do
    assert Adapter.names() == [:nats, :kafka, :rabbitmq, :redis, :mqtt, :aws_sns, :google_pubsub]
    assert Adapter.names() == Enum.uniq(Adapter.names())

    assert Adapter.wire_strings() == [
             "nats",
             "kafka",
             "amqp091",
             "rabbitmq",
             "redis",
             "mqtt",
             "aws_sns",
             "google_pubsub"
           ]

    assert Adapter.wire_strings() == Enum.uniq(Adapter.wire_strings())
  end

  test "wire-format names resolve to their canonical adapter" do
    assert Adapter.name_for_wire("nats") == :nats
    assert Adapter.name_for_wire("amqp091") == :rabbitmq
    assert Adapter.name_for_wire("rabbitmq") == :rabbitmq
    assert Adapter.name_for_wire("unknown") == nil
  end

  test "canonical names resolve to adapter modules" do
    for name <- Adapter.names() do
      module = Adapter.module_for(name)
      assert Code.ensure_loaded?(module)
      assert function_exported?(module, :publish, 1)
      assert function_exported?(module, :healthy?, 0)
    end
  end
end
