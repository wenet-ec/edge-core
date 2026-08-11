# edge_admin/lib/edge_admin/events/broker/topic_routing.ex
defmodule EdgeAdmin.Events.Broker.TopicRouting do
  @moduledoc "Pure routing rules shared by event broker adapters."

  @doc "Maps a catalog event type to its broker topic."
  @spec topic_for(String.t()) :: String.t()
  def topic_for("edge.node." <> _), do: "edge-nodes-events"
  def topic_for("edge.enrollment_key." <> _), do: "edge-nodes-events"
  def topic_for("edge.command_execution." <> _), do: "edge-commands-events"
  def topic_for("edge.self_update_request." <> _), do: "edge-self-updates-events"
  def topic_for("edge.ssh_username." <> _), do: "edge-ssh-events"
  def topic_for("edge.core." <> _), do: "edge-core-events"

  @doc "Returns the Kafka partition key selected from an event envelope."
  @spec partition_key_for(map()) :: String.t()
  def partition_key_for(%{"data" => %{"command_execution_id" => id}}) when is_binary(id), do: id
  def partition_key_for(%{"data" => %{"self_update_request_id" => id}}) when is_binary(id), do: id
  def partition_key_for(%{"data" => %{"enrollment_key_id" => id}}) when is_binary(id), do: id
  def partition_key_for(%{"data" => %{"node_id" => id}}) when is_binary(id), do: id
  def partition_key_for(_), do: ""
end
