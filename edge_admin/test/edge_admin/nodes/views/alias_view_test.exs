# edge_admin/test/edge_admin/nodes/views/alias_view_test.exs
defmodule EdgeAdmin.Nodes.Views.AliasViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Views.AliasView

  defp alias_fixture(overrides \\ %{}) do
    cluster = %Cluster{id: "cluster-uuid-1", name: "prod"}
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %Alias{
      id: "alias-uuid-1",
      name: "web",
      node_id: "node-uuid-1",
      cluster_id: cluster.id,
      cluster: cluster,
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      alias_record = alias_fixture()

      result = AliasView.render(alias_record)

      assert result.id == alias_record.id
      assert result.name == "web"
      assert result.node_id == "node-uuid-1"
      assert result.cluster_name == "prod"
      assert result.vpn_hostname == "node-web.cluster-prod.nm.internal"
      assert result.inserted_at == alias_record.inserted_at
      assert result.updated_at == alias_record.updated_at
    end

    test "vpn_hostname reflects the alias name and the preloaded cluster name" do
      alias_record =
        alias_fixture(%{name: "api", cluster: %Cluster{id: "c2", name: "staging"}})

      assert AliasView.render(alias_record).vpn_hostname ==
               "node-api.cluster-staging.nm.internal"
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = AliasView.render(alias_fixture())

      expected_keys = Enum.sort(~w(id name vpn_hostname node_id cluster_name inserted_at updated_at)a)
      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
