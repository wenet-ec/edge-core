# edge_admin/test/edge_admin/gateway_registry/reconciler_test.exs
defmodule EdgeAdmin.GatewayRegistry.ReconcilerTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.GatewayRegistry.Reconciler

  test "plans joins and leaves from current and assigned clusters" do
    plan = Reconciler.plan(MapSet.new(["shared", "leaving"]), ["shared", "joining"])

    assert plan.to_join == MapSet.new(["joining"])
    assert plan.to_leave == MapSet.new(["leaving"])
    assert plan.retained == MapSet.new(["shared"])
  end

  test "accepts ordinary enumerables and handles an empty topology" do
    assert Reconciler.plan([], []) == %{to_join: MapSet.new(), to_leave: MapSet.new(), retained: MapSet.new()}

    assert Reconciler.plan(["a", "b"], ["b", "c"]) == %{
             to_join: MapSet.new(["c"]),
             to_leave: MapSet.new(["a"]),
             retained: MapSet.new(["b"])
           }
  end

  test "is independent of input ordering" do
    first = Reconciler.plan(["a", "b"], ["b", "c"])
    second = Reconciler.plan(["b", "a"], ["c", "b"])

    assert first == second
  end
end
