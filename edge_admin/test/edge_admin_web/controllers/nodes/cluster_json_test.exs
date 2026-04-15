# edge_admin/test/edge_admin_web/controllers/nodes/cluster_json_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterJSONTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdminWeb.Controllers.Nodes.ClusterJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp fake_conn do
    Plug.Conn.assign(build_conn(), :request_id, "test-request-id")
  end

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(
      %Cluster{
        id: "cluster-uuid-1",
        name: "prod",
        ipv4_range: "100.64.1.0/24",
        nodes: [],
        inserted_at: @now,
        updated_at: @now
      },
      overrides
    )
  end

  defp fake_node(overrides \\ %{}) do
    Map.merge(
      %Node{
        id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        status: "healthy",
        id_type: "persistent"
      },
      overrides
    )
  end

  defp fake_meta(overrides \\ []) do
    struct(
      Flop.Meta,
      Keyword.merge(
        [
          current_page: 1,
          page_size: 20,
          total_count: 1,
          total_pages: 1,
          has_next_page?: false,
          has_previous_page?: false
        ],
        overrides
      )
    )
  end

  # -----------------------------------------------------------------------
  # show/1
  # -----------------------------------------------------------------------

  describe "show/1" do
    test "wraps cluster in %{data: ...}" do
      result = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster()})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster()}).data
      assert Map.has_key?(data, :id)
      assert Map.has_key?(data, :name)
      assert Map.has_key?(data, :ipv4_range)
      assert Map.has_key?(data, :node_limit)
      assert Map.has_key?(data, :node_count)
      assert Map.has_key?(data, :nodes)
      assert Map.has_key?(data, :network_name)
      assert Map.has_key?(data, :vpn_domain)
      assert Map.has_key?(data, :inserted_at)
      assert Map.has_key?(data, :updated_at)
    end

    test "scalar fields are passed through" do
      cluster = fake_cluster(%{name: "staging", ipv4_range: "100.64.2.0/24"})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      assert data.id == "cluster-uuid-1"
      assert data.name == "staging"
      assert data.ipv4_range == "100.64.2.0/24"
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end

    test "node_limit is passed through as nil when not set" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster()}).data
      assert data.node_limit == nil
    end

    test "node_limit is passed through when set" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster(%{node_limit: 25})}).data
      assert data.node_limit == 25
    end

    test "node_count is 0 when nodes is empty list" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster(%{nodes: []})}).data
      assert data.node_count == 0
    end

    test "node_count matches the number of nodes in the list" do
      nodes = [fake_node(), fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-ffffffffffff"})]
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster(%{nodes: nodes})}).data
      assert data.node_count == 2
    end

    test "network_name follows cluster-{name} format" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster(%{name: "prod"})}).data
      assert data.network_name == "cluster-prod"
    end

    test "vpn_domain follows cluster-{name}.nm.internal format" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster(%{name: "prod"})}).data
      assert data.vpn_domain == "cluster-prod.nm.internal"
    end

    test "nodes list is empty when cluster has no nodes" do
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: fake_cluster(%{nodes: []})}).data
      assert data.nodes == []
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — node_data inline composition
  # -----------------------------------------------------------------------

  describe "show/1 — node_data inside cluster" do
    test "each node has id, status, id_type, vpn_hostname" do
      node = fake_node()
      cluster = fake_cluster(%{name: "prod", nodes: [node]})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      node_data = hd(data.nodes)
      assert Map.has_key?(node_data, :id)
      assert Map.has_key?(node_data, :status)
      assert Map.has_key?(node_data, :id_type)
      assert Map.has_key?(node_data, :vpn_hostname)
    end

    test "node vpn_hostname uses node-{id}.cluster-{name}.nm.internal format" do
      node = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"})
      cluster = fake_cluster(%{name: "prod", nodes: [node]})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      node_data = hd(data.nodes)
      assert node_data.vpn_hostname == "node-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.cluster-prod.nm.internal"
    end

    test "node vpn_hostname uses cluster name from the parent cluster (not node's own cluster assoc)" do
      node = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"})
      cluster = fake_cluster(%{name: "staging", nodes: [node]})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      node_data = hd(data.nodes)
      assert node_data.vpn_hostname =~ "cluster-staging"
    end

    test "node status and id_type are passed through" do
      node = fake_node(%{status: "unhealthy", id_type: "random"})
      cluster = fake_cluster(%{nodes: [node]})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      node_data = hd(data.nodes)
      assert node_data.status == "unhealthy"
      assert node_data.id_type == "random"
    end

    test "multiple nodes all rendered in order" do
      node1 = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", status: "healthy"})
      node2 = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-ffffffffffff", status: "unhealthy"})
      cluster = fake_cluster(%{nodes: [node1, node2]})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      assert length(data.nodes) == 2

      assert Enum.map(data.nodes, & &1.id) == [
               "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
               "aaaaaaaa-bbbb-cccc-dddd-ffffffffffff"
             ]
    end

    test "node_data does NOT have keys beyond id, status, id_type, vpn_hostname" do
      node = fake_node()
      cluster = fake_cluster(%{nodes: [node]})
      data = ClusterJSON.show(%{conn: fake_conn(), cluster: cluster}).data
      node_data = hd(data.nodes)

      assert MapSet.equal?(
               MapSet.new(Map.keys(node_data)),
               MapSet.new([:id, :status, :id_type, :vpn_hostname])
             )
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — data array
  # -----------------------------------------------------------------------

  describe "index/1 — data array" do
    test "result has :data and :meta keys" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta()})
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :meta)
    end

    test "empty clusters produces empty data list" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta()})
      assert result.data == []
    end

    test "each cluster is rendered" do
      cluster = fake_cluster(%{name: "prod"})
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [cluster], meta: fake_meta()})
      assert length(result.data) == 1
      assert hd(result.data).name == "prod"
    end

    test "multiple clusters rendered in order" do
      clusters = [
        fake_cluster(%{id: "uuid-1", name: "prod"}),
        fake_cluster(%{id: "uuid-2", name: "staging"})
      ]

      result = ClusterJSON.index(%{conn: fake_conn(), clusters: clusters, meta: fake_meta()})
      assert length(result.data) == 2
      assert Enum.map(result.data, & &1.id) == ["uuid-1", "uuid-2"]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — pagination field renames
  # -----------------------------------------------------------------------

  describe "index/1 — pagination field renames from Flop.Meta" do
    test "current_page is renamed to page" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(current_page: 3)})
      assert Map.has_key?(result.meta.pagination, :page)
      refute Map.has_key?(result.meta.pagination, :current_page)
      assert result.meta.pagination.page == 3
    end

    test "total_count is renamed to total" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(total_count: 55)})
      assert Map.has_key?(result.meta.pagination, :total)
      refute Map.has_key?(result.meta.pagination, :total_count)
      assert result.meta.pagination.total == 55
    end

    test "has_next_page? is renamed to has_next" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(has_next_page?: true)})
      assert Map.has_key?(result.meta.pagination, :has_next)
      refute Map.has_key?(result.meta.pagination, :has_next_page?)
      assert result.meta.pagination.has_next == true
    end

    test "has_previous_page? is renamed to has_prev" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(has_previous_page?: true)})
      assert Map.has_key?(result.meta.pagination, :has_prev)
      refute Map.has_key?(result.meta.pagination, :has_previous_page?)
      assert result.meta.pagination.has_prev == true
    end

    test "page_size is passed through unchanged" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(page_size: 50)})
      assert result.meta.pagination.page_size == 50
    end

    test "total_pages is passed through unchanged" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(total_pages: 7)})
      assert result.meta.pagination.total_pages == 7
    end

    test "has_next false is preserved" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(has_next_page?: false)})
      assert result.meta.pagination.has_next == false
    end

    test "has_prev false is preserved" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta(has_previous_page?: false)})
      assert result.meta.pagination.has_prev == false
    end

    test "pagination has exactly the expected keys" do
      result = ClusterJSON.index(%{conn: fake_conn(), clusters: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.meta.pagination)),
               MapSet.new([:page, :page_size, :total, :total_pages, :has_next, :has_prev, :next_page, :prev_page])
             )
    end
  end
end
