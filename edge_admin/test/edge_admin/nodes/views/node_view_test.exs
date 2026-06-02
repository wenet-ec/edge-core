# edge_admin/test/edge_admin/nodes/views/node_view_test.exs
defmodule EdgeAdmin.Nodes.Views.NodeViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Views.NodeView

  # ---------------------------------------------------------------------------
  # Fixtures — bare structs, no DB. Views are pure transforms; we only need
  # the fields and preloads they actually read.
  # ---------------------------------------------------------------------------

  defp cluster_fixture(overrides \\ %{}) do
    Map.merge(
      %Cluster{
        id: "cluster-uuid-1",
        name: "prod"
      },
      Map.new(overrides, fn {k, v} -> {k, v} end)
    )
  end

  defp alias_fixture(node_id, cluster, name) do
    %Alias{
      id: "alias-uuid-#{name}",
      name: name,
      node_id: node_id,
      cluster_id: cluster.id,
      cluster: cluster
    }
  end

  defp node_fixture(overrides \\ %{}) do
    cluster = cluster_fixture()
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %Node{
      id: "node-uuid-1",
      cluster_id: cluster.id,
      cluster: cluster,
      aliases: [],
      netmaker_host_id: "host-1",
      id_type: :persistent,
      status: :healthy,
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9586,
      http_proxy_port: 8080,
      socks5_proxy_port: 1080,
      api_token: "token-abc",
      proxy_password: "pw-abc",
      version: "0.1.0",
      self_update_enabled: true,
      last_seen_at: now,
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # render/1 — happy path with all fields populated
  # ---------------------------------------------------------------------------

  describe "render/1" do
    test "produces every documented field with correct values" do
      cluster = cluster_fixture(%{name: "prod"})
      node = node_fixture(%{cluster: cluster})

      result = NodeView.render(node)

      # Identity / cluster reference.
      assert result.id == node.id
      assert result.cluster_name == "prod"
      assert result.netmaker_host_id == "host-1"
      assert result.id_type == "persistent"
      assert result.status == "healthy"

      # Computed hostnames — pinned exactly so a regression in the helper
      # composition surfaces immediately.
      assert result.node_name == "node-#{node.id}"
      assert result.vpn_hostname == "node-#{node.id}.cluster-prod.nm.internal"
      assert result.mdns_hostname == "node-#{node.id}.local"

      # Ports.
      assert result.http_port == 44_000
      assert result.ssh_port == 40_022
      assert result.host_metrics_port == 9100
      assert result.wireguard_metrics_port == 9586
      assert result.http_proxy_port == 8080
      assert result.socks5_proxy_port == 1080

      # Misc.
      assert result.version == "0.1.0"
      assert result.self_update_enabled == true
      assert result.last_seen_at == node.last_seen_at
      assert result.inserted_at == node.inserted_at
      assert result.updated_at == node.updated_at

      # Aliases — empty list when none preloaded.
      assert result.aliases == []
    end

    test "renders aliases as nested summaries with vpn_hostname" do
      cluster = cluster_fixture(%{name: "prod"})

      aliases = [
        alias_fixture("node-uuid-1", cluster, "web"),
        alias_fixture("node-uuid-1", cluster, "api")
      ]

      node = node_fixture(%{cluster: cluster, aliases: aliases})

      result = NodeView.render(node)

      assert length(result.aliases) == 2

      [web_alias, api_alias] = result.aliases

      assert web_alias.id == "alias-uuid-web"
      assert web_alias.name == "web"
      assert web_alias.vpn_hostname == "node-web.cluster-prod.nm.internal"

      assert api_alias.id == "alias-uuid-api"
      assert api_alias.name == "api"
      assert api_alias.vpn_hostname == "node-api.cluster-prod.nm.internal"
    end

    test "alias summary contains exactly the documented keys (id, name, vpn_hostname)" do
      cluster = cluster_fixture(%{name: "prod"})
      aliases = [alias_fixture("node-uuid-1", cluster, "web")]
      node = node_fixture(%{cluster: cluster, aliases: aliases})

      [alias_summary] = NodeView.render(node).aliases

      assert alias_summary |> Map.keys() |> Enum.sort() == [:id, :name, :vpn_hostname]
    end

    test "rendered map contains exactly the documented top-level keys" do
      node = node_fixture()

      result = NodeView.render(node)

      expected_keys = Enum.sort(~w(
          id node_name cluster_name netmaker_host_id id_type status
          vpn_hostname mdns_hostname
          http_port ssh_port host_metrics_port wireguard_metrics_port
          http_proxy_port socks5_proxy_port
          version self_update_enabled last_seen_at
          aliases inserted_at updated_at
        )a)

      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
