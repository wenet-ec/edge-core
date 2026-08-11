# edge_admin/test/edge_admin/edge_clusters/reconciliation_test.exs
defmodule EdgeAdmin.EdgeClusters.ReconciliationTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.EdgeClusters.Reconciliation

  test "plans joins and leaves from current and assigned clusters" do
    plan = Reconciliation.plan(MapSet.new(["shared", "leaving"]), ["shared", "joining"])

    assert plan.to_join == MapSet.new(["joining"])
    assert plan.to_leave == MapSet.new(["leaving"])
    assert plan.retained == MapSet.new(["shared"])
  end

  test "accepts ordinary enumerables and handles an empty topology" do
    assert Reconciliation.plan([], []) == %{to_join: MapSet.new(), to_leave: MapSet.new(), retained: MapSet.new()}

    assert Reconciliation.plan(["a", "b"], ["b", "c"]) == %{
             to_join: MapSet.new(["c"]),
             to_leave: MapSet.new(["a"]),
             retained: MapSet.new(["b"])
           }
  end

  test "is independent of input ordering" do
    first = Reconciliation.plan(["a", "b"], ["b", "c"])
    second = Reconciliation.plan(["b", "a"], ["c", "b"])

    assert first == second
  end
end
