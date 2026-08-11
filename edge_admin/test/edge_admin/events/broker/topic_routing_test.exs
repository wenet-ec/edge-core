# edge_admin/test/edge_admin/events/broker/topic_routing_test.exs
defmodule EdgeAdmin.Events.Broker.TopicRoutingTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Broker.TopicRouting

  test "maps every event domain to its canonical topic" do
    assert TopicRouting.topic_for("edge.node.registered") == "edge-nodes-events"
    assert TopicRouting.topic_for("edge.enrollment_key.verified") == "edge-nodes-events"
    assert TopicRouting.topic_for("edge.command_execution.completed") == "edge-commands-events"
    assert TopicRouting.topic_for("edge.self_update_request.completed") == "edge-self-updates-events"
    assert TopicRouting.topic_for("edge.ssh_username.verified") == "edge-ssh-events"
    assert TopicRouting.topic_for("edge.core.test") == "edge-core-events"
  end

  test "selects the most specific Kafka partition key" do
    assert TopicRouting.partition_key_for(%{
             "data" => %{"command_execution_id" => "execution-1", "node_id" => "node-1"}
           }) == "execution-1"

    assert TopicRouting.partition_key_for(%{"data" => %{"self_update_request_id" => "request-1"}}) == "request-1"
    assert TopicRouting.partition_key_for(%{"data" => %{"enrollment_key_id" => "key-1"}}) == "key-1"
    assert TopicRouting.partition_key_for(%{"data" => %{"node_id" => "node-1"}}) == "node-1"
    assert TopicRouting.partition_key_for(%{"data" => %{}}) == ""
  end
end
