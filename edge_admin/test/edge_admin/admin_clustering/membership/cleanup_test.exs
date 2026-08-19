# edge_admin/test/edge_admin/admin_clustering/membership/cleanup_test.exs
defmodule EdgeAdmin.AdminClustering.Membership.CleanupTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.AdminClustering.Membership.Cleanup

  defp node_with(host_id, lastcheckin) do
    %{"id" => "node-#{host_id}", "hostid" => host_id, "lastcheckin" => lastcheckin}
  end

  describe "zombie_node?/4" do
    test "fresh check-in is never a zombie" do
      now = 1_700_000_000
      node = node_with("h1", now - 10)

      refute Cleanup.zombie_node?(node, now, 120, [])
    end

    test "check-in older than threshold and unprotected → zombie" do
      now = 1_700_000_000
      node = node_with("h1", now - 200)

      assert Cleanup.zombie_node?(node, now, 120, [])
    end

    test "check-in exactly at threshold is NOT a zombie (strict greater-than)" do
      now = 1_700_000_000
      node = node_with("h1", now - 120)

      refute Cleanup.zombie_node?(node, now, 120, [])
    end

    test "protected hosts are never reaped, even when long-stale" do
      now = 1_700_000_000
      node = node_with("h1", now - 100_000)

      refute Cleanup.zombie_node?(node, now, 120, ["h1"])
    end

    test "protection only matches by host id, not arbitrary other ids" do
      now = 1_700_000_000
      node = node_with("h1", now - 200)

      assert Cleanup.zombie_node?(node, now, 120, ["other-host"])
    end

    test "accepts a MapSet for the protected set" do
      now = 1_700_000_000
      node = node_with("h1", now - 100_000)

      refute Cleanup.zombie_node?(node, now, 120, MapSet.new(["h1", "h2"]))
    end

    test "future-dated check-in (clock skew) yields negative age, never a zombie" do
      now = 1_700_000_000
      node = node_with("h1", now + 60)

      refute Cleanup.zombie_node?(node, now, 120, [])
    end
  end
end
