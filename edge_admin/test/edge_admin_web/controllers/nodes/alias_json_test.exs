# edge_admin/test/edge_admin_web/controllers/nodes/alias_json_test.exs
defmodule EdgeAdminWeb.Controllers.Nodes.AliasJSONTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdminWeb.Controllers.Nodes.AliasJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(%Cluster{id: "cluster-uuid-1", name: "prod", ipv4_range: "100.64.1.0/24"}, overrides)
  end

  defp fake_alias(overrides \\ %{}) do
    Map.merge(
      %Alias{
        id: "alias-uuid-1",
        name: "web",
        node_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        cluster_id: "cluster-uuid-1",
        cluster: fake_cluster(),
        inserted_at: @now,
        updated_at: @now
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
    test "wraps alias in %{data: ...}" do
      result = AliasJSON.show(%{alias: fake_alias()})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      data = AliasJSON.show(%{alias: fake_alias()}).data

      for key <- [:id, :name, :dns_hostname, :node_id, :cluster_name, :inserted_at, :updated_at] do
        assert Map.has_key?(data, key), "expected key #{inspect(key)} to be present"
      end
    end

    test "scalar fields are passed through correctly" do
      alias_record =
        fake_alias(%{
          name: "api",
          node_id: "11111111-2222-3333-4444-555555555555",
          cluster: fake_cluster(%{name: "staging"})
        })

      data = AliasJSON.show(%{alias: alias_record}).data
      assert data.id == "alias-uuid-1"
      assert data.name == "api"
      assert data.node_id == "11111111-2222-3333-4444-555555555555"
      assert data.cluster_name == "staging"
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end

    test "cluster_name comes from preloaded cluster" do
      alias_record = fake_alias(%{cluster: fake_cluster(%{name: "dev"})})
      data = AliasJSON.show(%{alias: alias_record}).data
      assert data.cluster_name == "dev"
    end
  end

  # -----------------------------------------------------------------------
  # show/1 — dns_hostname delegation
  # -----------------------------------------------------------------------

  describe "show/1 — dns_hostname" do
    test "dns_hostname is node-{alias_name}.cluster-{cluster_name}.nm.internal" do
      alias_record = fake_alias(%{name: "web", cluster: fake_cluster(%{name: "prod"})})
      data = AliasJSON.show(%{alias: alias_record}).data
      assert data.dns_hostname == "node-web.cluster-prod.nm.internal"
    end

    test "dns_hostname reflects the alias name, not the node id" do
      alias_record = fake_alias(%{name: "my-service", cluster: fake_cluster(%{name: "prod"})})
      data = AliasJSON.show(%{alias: alias_record}).data
      assert data.dns_hostname == "node-my-service.cluster-prod.nm.internal"
    end

    test "dns_hostname uses the cluster name from preloaded cluster" do
      alias_record = fake_alias(%{name: "web", cluster: fake_cluster(%{name: "staging"})})
      data = AliasJSON.show(%{alias: alias_record}).data
      assert data.dns_hostname =~ "cluster-staging"
    end

    test "dns_hostname has node- prefix on alias name" do
      alias_record = fake_alias(%{name: "db"})
      data = AliasJSON.show(%{alias: alias_record}).data
      assert String.starts_with?(data.dns_hostname, "node-db.")
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — data array
  # -----------------------------------------------------------------------

  describe "index/1 — data array" do
    test "result has :data and :pagination keys" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta()})
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :pagination)
    end

    test "empty aliases produces empty data list" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta()})
      assert result.data == []
    end

    test "each alias is rendered" do
      alias_record = fake_alias(%{name: "web"})
      result = AliasJSON.index(%{aliases: [alias_record], meta: fake_meta()})
      assert length(result.data) == 1
      assert hd(result.data).name == "web"
    end

    test "multiple aliases rendered in order" do
      alias1 = fake_alias(%{id: "alias-1", name: "web"})
      alias2 = fake_alias(%{id: "alias-2", name: "api"})
      result = AliasJSON.index(%{aliases: [alias1, alias2], meta: fake_meta()})
      assert length(result.data) == 2
      assert Enum.map(result.data, & &1.id) == ["alias-1", "alias-2"]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — pagination field renames
  # -----------------------------------------------------------------------

  describe "index/1 — pagination field renames from Flop.Meta" do
    test "current_page is renamed to page" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(current_page: 4)})
      assert Map.has_key?(result.pagination, :page)
      refute Map.has_key?(result.pagination, :current_page)
      assert result.pagination.page == 4
    end

    test "total_count is renamed to total" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(total_count: 10)})
      assert Map.has_key?(result.pagination, :total)
      refute Map.has_key?(result.pagination, :total_count)
      assert result.pagination.total == 10
    end

    test "has_next_page? is renamed to has_next" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(has_next_page?: true)})
      assert Map.has_key?(result.pagination, :has_next)
      refute Map.has_key?(result.pagination, :has_next_page?)
      assert result.pagination.has_next == true
    end

    test "has_previous_page? is renamed to has_prev" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(has_previous_page?: true)})
      assert Map.has_key?(result.pagination, :has_prev)
      refute Map.has_key?(result.pagination, :has_previous_page?)
      assert result.pagination.has_prev == true
    end

    test "page_size is passed through unchanged" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(page_size: 25)})
      assert result.pagination.page_size == 25
    end

    test "total_pages is passed through unchanged" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(total_pages: 3)})
      assert result.pagination.total_pages == 3
    end

    test "has_next false is preserved" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(has_next_page?: false)})
      assert result.pagination.has_next == false
    end

    test "has_prev false is preserved" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta(has_previous_page?: false)})
      assert result.pagination.has_prev == false
    end

    test "pagination has exactly the expected keys" do
      result = AliasJSON.index(%{aliases: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.pagination)),
               MapSet.new([:page, :page_size, :total, :total_pages, :has_next, :has_prev])
             )
    end
  end
end
