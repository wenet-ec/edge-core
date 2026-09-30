# edge_admin/test/edge_admin/vpn_test.exs
defmodule EdgeAdmin.VpnTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn
  # select_host_id/3

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

  describe "classify_create_network_400/1" do
    test "CIDR collision returns a conflict" do
      body = %{"Message" => "network cidr already in use by network-foo"}

      assert Vpn.classify_create_network_400(body) ==
               {:error, {:conflict, "network CIDR overlaps an existing Edge VPN network"}}
    end

    test "name collision response → :already_exists" do
      body = %{"Message" => "invalid network name: already exists"}
      assert Vpn.classify_create_network_400(body) == {:error, :already_exists}
    end

    test "substring match — phrase can appear anywhere in the message" do
      body = %{"Message" => "validation failed: network cidr already in use, retry"}
      assert {:error, {:conflict, _reason}} = Vpn.classify_create_network_400(body)
    end

    test "matching is case-sensitive — wrong case falls through" do
      body = %{"Message" => "Network CIDR already in use"}
      assert Vpn.classify_create_network_400(body) == {:error, :service_unavailable}
    end

    test "unknown 400 message → :service_unavailable" do
      body = %{"Message" => "some other error"}
      assert Vpn.classify_create_network_400(body) == {:error, :service_unavailable}
    end

    test "binary body is treated as the message directly" do
      assert Vpn.classify_create_network_400("network cidr already in use") ==
               {:error, {:conflict, "network CIDR overlaps an existing Edge VPN network"}}
    end

    test "empty / unrecognised body shape → :service_unavailable" do
      assert Vpn.classify_create_network_400(%{}) == {:error, :service_unavailable}
      assert Vpn.classify_create_network_400(nil) == {:error, :service_unavailable}
      assert Vpn.classify_create_network_400("") == {:error, :service_unavailable}
    end
  end

  describe "check_network_ranges/3" do
    test "ignores the target network and detects overlap with another network" do
      networks = [
        %{"netid" => "admin-cluster-core", "addressrange" => "100.64.0.0/24", "addressrange6" => "fd7a:1::/64"},
        %{"netid" => "cluster-west", "addressrange" => "100.65.0.0/24", "addressrange6" => "fd7a:2::/64"}
      ]

      assert Vpn.check_network_ranges("admin-cluster-core", %{addressrange: "100.64.0.0/24"}, networks) == :ok

      assert {:error, {:conflict, message}} =
               Vpn.check_network_ranges("admin-cluster-new", %{addressrange: "100.64.0.128/25"}, networks)

      assert message =~ "cluster-core"
      assert message =~ "100.64.0.128/25"
    end

    test "detects IPv6 overlap and allows disjoint ranges" do
      networks = [
        %{"netid" => "cluster-west", "addressrange" => "100.65.0.0/24", "addressrange6" => "fd7a:2::/64"}
      ]

      assert {:error, {:conflict, message}} =
               Vpn.check_network_ranges("admin-cluster-new", %{addressrange6: "fd7a:2::1/128"}, networks)

      assert message =~ "IPv6 range"

      assert Vpn.check_network_ranges(
               "admin-cluster-new",
               %{addressrange: "100.66.0.0/24", addressrange6: "fd7a:3::/64"},
               networks
             ) == :ok
    end
  end

  describe "classify_delete_node_400/1" do
    test "missing-node validation error → :not_found" do
      body = %{
        "Message" => "error fetching node during parameter validation: record not found"
      }

      assert Vpn.classify_delete_node_400(body) == {:error, :not_found}
    end

    test "other bad requests remain service_unavailable" do
      assert Vpn.classify_delete_node_400(%{"Message" => "invalid node ID"}) ==
               {:error, :service_unavailable}
    end
  end

  describe "normalize_edge_vpn_error/1" do
    test "ok tuple is preserved" do
      assert Vpn.normalize_edge_vpn_error({:ok, %{"netid" => "x"}}) == {:ok, %{"netid" => "x"}}
      assert Vpn.normalize_edge_vpn_error({:ok, []}) == {:ok, []}
    end

    test ":not_found is preserved (so callers can render 404)" do
      assert Vpn.normalize_edge_vpn_error({:error, :not_found}) == {:error, :not_found}
    end

    test "every other error collapses to :service_unavailable" do
      assert Vpn.normalize_edge_vpn_error({:error, :timeout}) == {:error, :service_unavailable}
      assert Vpn.normalize_edge_vpn_error({:error, :econnrefused}) == {:error, :service_unavailable}
      assert Vpn.normalize_edge_vpn_error({:error, %{status: 500}}) == {:error, :service_unavailable}
      assert Vpn.normalize_edge_vpn_error({:error, "anything"}) == {:error, :service_unavailable}
    end

    test "narrows Api.normalize — :conflict and {:bad_request, _} both flatten" do
      assert Vpn.normalize_edge_vpn_error({:error, :conflict}) == {:error, :service_unavailable}

      assert Vpn.normalize_edge_vpn_error({:error, {:bad_request, %{"Message" => "x"}}}) ==
               {:error, :service_unavailable}
    end
  end
end
