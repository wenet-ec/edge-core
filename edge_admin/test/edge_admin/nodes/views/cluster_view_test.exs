# edge_admin/test/edge_admin/nodes/views/cluster_view_test.exs
defmodule EdgeAdmin.Nodes.Views.ClusterViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Views.ClusterView

  defp cluster_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %Cluster{
      id: "cluster-uuid-1",
      name: "prod",
      ipv4_range: "100.64.1.0/24",
      node_limit: nil,
      nodes: [],
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  defp node_fixture(overrides \\ %{}) do
    base = %Node{
      id: "node-uuid-1",
      id_type: :persistent,
      status: :healthy
    }

    struct(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # render/1
  # ---------------------------------------------------------------------------

  describe "render/1" do
    test "produces every documented field with correct values" do
      cluster = cluster_fixture(%{name: "prod", node_limit: 50})

      result = ClusterView.render(cluster)

      assert result.id == cluster.id
      assert result.name == "prod"
      assert result.ipv4_range == "100.64.1.0/24"
      assert result.node_limit == 50
      assert result.node_count == 0
      assert result.nodes == []
      assert result.network_name == "cluster-prod"
      assert result.vpn_domain == "cluster-prod.nm.internal"
      assert result.inserted_at == cluster.inserted_at
      assert result.updated_at == cluster.updated_at
    end

    test "node_count reflects the length of the preloaded nodes list" do
      cluster =
        cluster_fixture(%{
          nodes: [node_fixture(%{id: "n1"}), node_fixture(%{id: "n2"}), node_fixture(%{id: "n3"})]
        })

      result = ClusterView.render(cluster)

      assert result.node_count == 3
      assert length(result.nodes) == 3
    end

    test "unloaded nodes association renders as an empty nodes list" do
      cluster = struct(Cluster, cluster_fixture() |> Map.from_struct() |> Map.delete(:nodes))

      result = ClusterView.render(cluster)

      assert result.node_count == 0
      assert result.nodes == []
    end

    test "node summaries carry id, status, id_type, and vpn_hostname" do
      cluster = cluster_fixture(%{name: "prod", nodes: [node_fixture(%{id: "abc-123"})]})

      [node_summary] = ClusterView.render(cluster).nodes

      assert node_summary.id == "abc-123"
      assert node_summary.status == "healthy"
      assert node_summary.id_type == "persistent"
      assert node_summary.vpn_hostname == "node-abc-123.cluster-prod.nm.internal"
    end

    test "node summary contains exactly the documented keys" do
      cluster = cluster_fixture(%{nodes: [node_fixture()]})

      [node_summary] = ClusterView.render(cluster).nodes

      assert node_summary |> Map.keys() |> Enum.sort() == [:id, :id_type, :status, :vpn_hostname]
    end

    test "node_limit nil is preserved as nil (not coerced)" do
      cluster = cluster_fixture(%{node_limit: nil})

      assert ClusterView.render(cluster).node_limit == nil
    end

    test "rendered map contains exactly the documented top-level keys" do
      cluster = cluster_fixture()

      result = ClusterView.render(cluster)

      expected_keys =
        Enum.sort(~w(id name ipv4_range node_limit node_count nodes network_name vpn_domain inserted_at updated_at)a)

      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
