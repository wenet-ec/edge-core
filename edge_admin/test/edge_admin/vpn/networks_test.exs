# edge_admin/test/edge_admin/vpn/networks_test.exs
defmodule EdgeAdmin.Vpn.NetworksTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn.Networks

  describe "classify_create_network_400/1" do
    test "classifies CIDR and name collisions" do
      assert Networks.classify_create_network_400(%{"Message" => "network cidr already in use"}) ==
               {:error, {:conflict, "network CIDR overlaps an existing Edge VPN network"}}

      assert Networks.classify_create_network_400(%{"Message" => "invalid network name: already exists"}) ==
               {:error, :already_exists}
    end

    test "returns service unavailable for unrecognized responses" do
      for body <- [%{"Message" => "other error"}, %{}, nil, ""] do
        assert Networks.classify_create_network_400(body) == {:error, :service_unavailable}
      end
    end

    test "matches a recognized phrase within a longer message" do
      body = %{"Message" => "validation failed: network cidr already in use, retry"}
      assert {:error, {:conflict, _reason}} = Networks.classify_create_network_400(body)
    end

    test "message matching is case-sensitive" do
      body = %{"Message" => "Network CIDR already in use"}
      assert Networks.classify_create_network_400(body) == {:error, :service_unavailable}
    end

    test "accepts a binary response body as the message" do
      assert Networks.classify_create_network_400("network cidr already in use") ==
               {:error, {:conflict, "network CIDR overlaps an existing Edge VPN network"}}
    end
  end

  describe "check_network_ranges/3" do
    test "ignores the target network and rejects overlapping ranges" do
      networks = [
        %{"netid" => "admin-cluster-core", "addressrange" => "100.64.0.0/24", "addressrange6" => "fd7a:1::/64"},
        %{"netid" => "cluster-west", "addressrange" => "100.65.0.0/24", "addressrange6" => "fd7a:2::/64"}
      ]

      assert Networks.check_network_ranges("admin-cluster-core", %{addressrange: "100.64.0.0/24"}, networks) == :ok

      assert {:error, {:conflict, message}} =
               Networks.check_network_ranges("admin-cluster-new", %{addressrange: "100.64.0.128/25"}, networks)

      assert message =~ "cluster-core"
      assert message =~ "100.64.0.128/25"
    end

    test "rejects overlapping IPv6 and allows disjoint ranges" do
      networks = [%{"netid" => "cluster-west", "addressrange" => "100.65.0.0/24", "addressrange6" => "fd7a:2::/64"}]

      assert {:error, {:conflict, message}} =
               Networks.check_network_ranges("admin-cluster-new", %{addressrange6: "fd7a:2::1/128"}, networks)

      assert message =~ "IPv6 range"

      assert Networks.check_network_ranges(
               "admin-cluster-new",
               %{addressrange: "100.66.0.0/24", addressrange6: "fd7a:3::/64"},
               networks
             ) == :ok
    end
  end

  describe "classify_delete_node_400/1" do
    test "maps missing-node validation errors to not found" do
      body = %{"Message" => "error fetching node during parameter validation: record not found"}
      assert Networks.classify_delete_node_400(body) == {:error, :not_found}
    end

    test "keeps other bad requests as service unavailable" do
      assert Networks.classify_delete_node_400(%{"Message" => "invalid node ID"}) ==
               {:error, :service_unavailable}
    end
  end
end
