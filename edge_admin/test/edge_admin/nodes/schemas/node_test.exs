# edge_admin/test/edge_admin/nodes/schemas/node_test.exs
defmodule EdgeAdmin.Nodes.Schemas.NodeTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(%Cluster{id: "cluster-uuid-1", name: "prod", ipv4_range: "100.64.1.0/24"}, overrides)
  end

  defp fake_node(overrides \\ %{}) do
    Map.merge(
      %Node{
        id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        cluster: fake_cluster()
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # node_name/1
  # ---------------------------------------------------------------------------

  describe "node_name/1" do
    test "returns node-{id} format" do
      node = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"})
      assert Node.node_name(node) == "node-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    end

    test "uses node id, not cluster name" do
      node = fake_node(%{id: "11111111-2222-3333-4444-555555555555", cluster: fake_cluster(%{name: "staging"})})
      assert Node.node_name(node) == "node-11111111-2222-3333-4444-555555555555"
    end

    test "always starts with node-" do
      assert String.starts_with?(Node.node_name(fake_node()), "node-")
    end
  end

  # ---------------------------------------------------------------------------
  # vpn_hostname/1
  # ---------------------------------------------------------------------------

  describe "vpn_hostname/1" do
    test "returns node-{id}.cluster-{cluster_name}.nm.internal" do
      node =
        fake_node(%{
          id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          cluster: fake_cluster(%{name: "prod"})
        })

      assert Node.vpn_hostname(node) == "node-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.cluster-prod.nm.internal"
    end

    test "cluster name is included in the hostname" do
      node = fake_node(%{cluster: fake_cluster(%{name: "staging"})})
      assert Node.vpn_hostname(node) =~ "cluster-staging"
    end

    test "node id is included in the hostname" do
      node = fake_node(%{id: "11111111-2222-3333-4444-555555555555"})
      assert Node.vpn_hostname(node) =~ "11111111-2222-3333-4444-555555555555"
    end

    test "ends with configured VPN domain (nm.internal)" do
      node = fake_node()
      assert String.ends_with?(Node.vpn_hostname(node), ".nm.internal")
    end

    test "changes when cluster name changes" do
      node_prod = fake_node(%{cluster: fake_cluster(%{name: "prod"})})
      node_dev = fake_node(%{cluster: fake_cluster(%{name: "dev"})})
      refute Node.vpn_hostname(node_prod) == Node.vpn_hostname(node_dev)
    end
  end

  # ---------------------------------------------------------------------------
  # mdns_hostname/1
  # ---------------------------------------------------------------------------

  describe "mdns_hostname/1" do
    test "returns node-{id}.local" do
      node = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"})
      assert Node.mdns_hostname(node) == "node-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.local"
    end

    test "always ends with .local" do
      assert String.ends_with?(Node.mdns_hostname(fake_node()), ".local")
    end

    test "always starts with node-" do
      assert String.starts_with?(Node.mdns_hostname(fake_node()), "node-")
    end

    test "does not contain cluster name" do
      node = fake_node(%{cluster: fake_cluster(%{name: "prod"})})
      refute Node.mdns_hostname(node) =~ "cluster"
    end

    test "is independent of cluster — same id gives same mdns_hostname regardless of cluster" do
      node_prod = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", cluster: fake_cluster(%{name: "prod"})})
      node_dev = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", cluster: fake_cluster(%{name: "dev"})})
      assert Node.mdns_hostname(node_prod) == Node.mdns_hostname(node_dev)
    end
  end

  # ---------------------------------------------------------------------------
  # hostname distinctness
  # ---------------------------------------------------------------------------

  describe "hostname distinctness" do
    test "vpn_hostname and mdns_hostname are different" do
      node = fake_node()
      refute Node.vpn_hostname(node) == Node.mdns_hostname(node)
    end
  end
end
