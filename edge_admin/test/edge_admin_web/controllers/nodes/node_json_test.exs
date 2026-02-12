defmodule EdgeAdminWeb.Controllers.Nodes.NodeJSONTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdminWeb.Controllers.Nodes.NodeJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(%Cluster{id: "cluster-uuid-1", name: "prod", ipv4_range: "100.64.1.0/24"}, overrides)
  end

  defp fake_node(overrides \\ %{}) do
    Map.merge(
      %Node{
        id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        id_type: "persistent",
        status: "healthy",
        netmaker_host_id: "host-uuid-1",
        http_port: 80,
        ssh_port: 40_022,
        host_metrics_port: 9100,
        wireguard_metrics_port: 9586,
        http_proxy_port: 8080,
        socks5_proxy_port: 1080,
        api_token: "tok-abc123",
        proxy_password: "proxy-pass",
        version: "1.2.3",
        self_update_enabled: false,
        relay_enabled: false,
        last_seen_at: @now,
        aliases: [],
        cluster: fake_cluster(),
        inserted_at: @now,
        updated_at: @now
      },
      overrides
    )
  end

  defp fake_alias(overrides \\ %{}) do
    Map.merge(
      %Alias{
        id: "alias-uuid-1",
        name: "web",
        node_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        cluster: fake_cluster()
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
    test "wraps node in %{data: ...}" do
      result = NodeJSON.show(%{node: fake_node()})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      data = NodeJSON.show(%{node: fake_node()}).data

      for key <- [
            :id,
            :node_name,
            :cluster_name,
            :netmaker_host_id,
            :id_type,
            :status,
            :dns_hostname,
            :http_port,
            :ssh_port,
            :host_metrics_port,
            :wireguard_metrics_port,
            :http_proxy_port,
            :socks5_proxy_port,
            :api_token,
            :proxy_password,
            :version,
            :self_update_enabled,
            :relay_enabled,
            :last_seen_at,
            :aliases,
            :inserted_at,
            :updated_at
          ] do
        assert Map.has_key?(data, key), "expected key #{inspect(key)} to be present"
      end
    end

    test "scalar fields are passed through correctly" do
      node =
        fake_node(%{
          id_type: "random",
          status: "unhealthy",
          http_port: 8000,
          ssh_port: 22,
          version: "2.0.0",
          self_update_enabled: true,
          relay_enabled: true,
          api_token: "tok-xyz",
          proxy_password: "secret"
        })

      data = NodeJSON.show(%{node: node}).data
      assert data.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      assert data.id_type == "random"
      assert data.status == "unhealthy"
      assert data.http_port == 8000
      assert data.ssh_port == 22
      assert data.version == "2.0.0"
      assert data.self_update_enabled == true
      assert data.relay_enabled == true
      assert data.api_token == "tok-xyz"
      assert data.proxy_password == "secret"
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end

    test "nil last_seen_at is passed through" do
      data = NodeJSON.show(%{node: fake_node(%{last_seen_at: nil})}).data
      assert data.last_seen_at == nil
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — node_name delegation
  # -----------------------------------------------------------------------

  describe "show/1 — node_name" do
    test "node_name is node-{id} format" do
      data = NodeJSON.show(%{node: fake_node()}).data
      assert data.node_name == "node-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    end

    test "node_name uses the node id" do
      node = fake_node(%{id: "11111111-2222-3333-4444-555555555555"})
      data = NodeJSON.show(%{node: node}).data
      assert data.node_name == "node-11111111-2222-3333-4444-555555555555"
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — cluster_name
  # -----------------------------------------------------------------------

  describe "show/1 — cluster_name" do
    test "cluster_name is taken from preloaded cluster" do
      node = fake_node(%{cluster: fake_cluster(%{name: "staging"})})
      data = NodeJSON.show(%{node: node}).data
      assert data.cluster_name == "staging"
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — dns_hostname delegation
  # -----------------------------------------------------------------------

  describe "show/1 — dns_hostname" do
    test "dns_hostname is node-{id}.cluster-{cluster_name}.nm.internal" do
      node =
        fake_node(%{
          id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          cluster: fake_cluster(%{name: "prod"})
        })

      data = NodeJSON.show(%{node: node}).data
      assert data.dns_hostname == "node-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.cluster-prod.nm.internal"
    end

    test "dns_hostname changes when cluster name changes" do
      node =
        fake_node(%{
          id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          cluster: fake_cluster(%{name: "dev"})
        })

      data = NodeJSON.show(%{node: node}).data
      assert data.dns_hostname =~ "cluster-dev"
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — aliases rendering
  # -----------------------------------------------------------------------

  describe "show/1 — aliases" do
    test "aliases is empty list when node has no aliases" do
      data = NodeJSON.show(%{node: fake_node(%{aliases: []})}).data
      assert data.aliases == []
    end

    test "each alias has id, name, dns_hostname" do
      alias_record = fake_alias(%{name: "web"})
      node = fake_node(%{aliases: [alias_record]})
      data = NodeJSON.show(%{node: node}).data
      alias_data = hd(data.aliases)
      assert Map.has_key?(alias_data, :id)
      assert Map.has_key?(alias_data, :name)
      assert Map.has_key?(alias_data, :dns_hostname)
    end

    test "alias dns_hostname is node-{alias_name}.cluster-{cluster_name}.nm.internal" do
      alias_record = fake_alias(%{name: "web", cluster: fake_cluster(%{name: "prod"})})
      node = fake_node(%{aliases: [alias_record]})
      data = NodeJSON.show(%{node: node}).data
      alias_data = hd(data.aliases)
      assert alias_data.dns_hostname == "node-web.cluster-prod.nm.internal"
    end

    test "alias name is passed through" do
      alias_record = fake_alias(%{name: "my-service"})
      node = fake_node(%{aliases: [alias_record]})
      data = NodeJSON.show(%{node: node}).data
      alias_data = hd(data.aliases)
      assert alias_data.name == "my-service"
    end

    test "multiple aliases all rendered in order" do
      alias1 = fake_alias(%{id: "alias-1", name: "web"})
      alias2 = fake_alias(%{id: "alias-2", name: "api"})
      node = fake_node(%{aliases: [alias1, alias2]})
      data = NodeJSON.show(%{node: node}).data
      assert length(data.aliases) == 2
      assert Enum.map(data.aliases, & &1.id) == ["alias-1", "alias-2"]
    end

    test "alias_data has exactly id, name, dns_hostname — no extra fields" do
      alias_record = fake_alias()
      node = fake_node(%{aliases: [alias_record]})
      data = NodeJSON.show(%{node: node}).data
      alias_data = hd(data.aliases)

      assert MapSet.equal?(
               MapSet.new(Map.keys(alias_data)),
               MapSet.new([:id, :name, :dns_hostname])
             )
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — data array
  # -----------------------------------------------------------------------

  describe "index/1 — data array" do
    test "result has :data and :pagination keys" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta()})
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :pagination)
    end

    test "empty nodes produces empty data list" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta()})
      assert result.data == []
    end

    test "each node is rendered" do
      node = fake_node(%{status: "healthy"})
      result = NodeJSON.index(%{nodes: [node], meta: fake_meta()})
      assert length(result.data) == 1
      assert hd(result.data).status == "healthy"
    end

    test "multiple nodes rendered in order" do
      node1 = fake_node(%{id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"})
      node2 = fake_node(%{id: "11111111-2222-3333-4444-555555555555"})
      result = NodeJSON.index(%{nodes: [node1, node2], meta: fake_meta()})
      assert length(result.data) == 2

      assert Enum.map(result.data, & &1.id) == [
               "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
               "11111111-2222-3333-4444-555555555555"
             ]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — pagination field renames
  # -----------------------------------------------------------------------

  describe "index/1 — pagination field renames from Flop.Meta" do
    test "current_page is renamed to page" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(current_page: 2)})
      assert Map.has_key?(result.pagination, :page)
      refute Map.has_key?(result.pagination, :current_page)
      assert result.pagination.page == 2
    end

    test "total_count is renamed to total" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(total_count: 99)})
      assert Map.has_key?(result.pagination, :total)
      refute Map.has_key?(result.pagination, :total_count)
      assert result.pagination.total == 99
    end

    test "has_next_page? is renamed to has_next" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(has_next_page?: true)})
      assert Map.has_key?(result.pagination, :has_next)
      refute Map.has_key?(result.pagination, :has_next_page?)
      assert result.pagination.has_next == true
    end

    test "has_previous_page? is renamed to has_prev" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(has_previous_page?: true)})
      assert Map.has_key?(result.pagination, :has_prev)
      refute Map.has_key?(result.pagination, :has_previous_page?)
      assert result.pagination.has_prev == true
    end

    test "page_size is passed through unchanged" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(page_size: 50)})
      assert result.pagination.page_size == 50
    end

    test "total_pages is passed through unchanged" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(total_pages: 5)})
      assert result.pagination.total_pages == 5
    end

    test "has_next false is preserved" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(has_next_page?: false)})
      assert result.pagination.has_next == false
    end

    test "has_prev false is preserved" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta(has_previous_page?: false)})
      assert result.pagination.has_prev == false
    end

    test "pagination has exactly the expected keys" do
      result = NodeJSON.index(%{nodes: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.pagination)),
               MapSet.new([:page, :page_size, :total, :total_pages, :has_next, :has_prev])
             )
    end
  end
end
