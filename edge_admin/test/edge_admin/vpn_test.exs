# edge_admin/test/edge_admin/vpn_test.exs
defmodule EdgeAdmin.VpnTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn

  # ---------------------------------------------------------------------------
  # select_host_id/3
  # ---------------------------------------------------------------------------

  describe "select_host_id/3" do
    test "returns nil when no host matches hostname" do
      assert Vpn.select_host_id([], [], "node-abc") == nil
    end

    test "returns the only matching host" do
      hosts = [%{"id" => "h1", "name" => "node-abc"}]

      assert Vpn.select_host_id(hosts, [], "node-abc") == "h1"
    end

    test "prefers connected host when duplicate hostnames exist" do
      hosts = [
        %{"id" => "stale", "name" => "node-abc"},
        %{"id" => "live", "name" => "node-abc"}
      ]

      nodes = [
        %{
          "hostid" => "stale",
          "connected" => false,
          "lastmodified" => 100,
          "lastcheckin" => 100,
          "lastpeerupdate" => 100
        },
        %{"hostid" => "live", "connected" => true, "lastmodified" => 90, "lastcheckin" => 90, "lastpeerupdate" => 90}
      ]

      assert Vpn.select_host_id(hosts, nodes, "node-abc") == "live"
    end

    test "uses node recency as a tie-breaker for duplicate disconnected hosts" do
      hosts = [
        %{"id" => "old", "name" => "node-abc"},
        %{"id" => "new", "name" => "node-abc"}
      ]

      nodes = [
        %{
          "hostid" => "old",
          "connected" => false,
          "lastmodified" => 100,
          "lastcheckin" => 100,
          "lastpeerupdate" => 100
        },
        %{"hostid" => "new", "connected" => false, "lastmodified" => 200, "lastcheckin" => 150, "lastpeerupdate" => 125}
      ]

      assert Vpn.select_host_id(hosts, nodes, "node-abc") == "new"
    end
  end
end
