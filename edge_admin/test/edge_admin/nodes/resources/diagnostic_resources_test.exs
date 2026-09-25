# edge_admin/test/edge_admin/nodes/resources/diagnostic_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.DiagnosticResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.DiagnosticResources
  alias EdgeAdmin.Test.Fixtures

  defp insert_node! do
    cluster = Fixtures.insert_cluster!(%{name: Fixtures.unique_name("diagnostics")})
    Fixtures.insert_node!(cluster.id, %{version: "edge-1.0.0"})
  end

  defp insert_diagnostic!(node, updated_at) do
    Fixtures.insert_node_diagnostic!(node.id, %{inserted_at: updated_at, updated_at: updated_at})
  end

  test "returns reports at the freshness cutoff and excludes older reports" do
    now = ~U[2026-02-01 12:00:00Z]
    fresh_node = insert_node!()
    stale_node = insert_node!()
    fresh = insert_diagnostic!(fresh_node, DateTime.shift(now, minute: -5))
    _stale = insert_diagnostic!(stale_node, DateTime.shift(now, second: -301))

    assert DiagnosticResources.get_recent(fresh_node.id, now).id == fresh.id
    assert DiagnosticResources.get_recent(stale_node.id, now) == nil
  end
end
