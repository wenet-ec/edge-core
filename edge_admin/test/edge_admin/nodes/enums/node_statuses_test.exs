# edge_admin/test/edge_admin/nodes/enums/node_statuses_test.exs
defmodule EdgeAdmin.Nodes.Enums.NodeStatusesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Enums.NodeStatuses

  test "statuses/0 returns all node health statuses in canonical order" do
    assert NodeStatuses.statuses() == [:healthy, :unhealthy, :unreachable]
  end

  test "reachable_statuses/0 excludes unreachable nodes" do
    assert NodeStatuses.reachable_statuses() == [:healthy, :unhealthy]
  end

  test "status_strings/0 mirrors statuses/0 in wire format" do
    assert NodeStatuses.status_strings() == Enum.map(NodeStatuses.statuses(), &Atom.to_string/1)
  end

  test "reachable_status_strings/0 mirrors reachable_statuses/0 in wire format" do
    assert NodeStatuses.reachable_status_strings() ==
             Enum.map(NodeStatuses.reachable_statuses(), &Atom.to_string/1)
  end
end
