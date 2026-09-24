# edge_admin/test/edge_admin/nodes/resources/alias_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.AliasResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.AliasResources
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp insert_cluster!(name, attrs \\ %{}) do
    sequence = System.unique_integer([:positive, :monotonic])

    defaults = %{
      id: Ecto.UUID.generate(),
      name: name,
      ipv4_range: "100.64.#{rem(sequence, 200)}.0/24",
      ipv6_range: "fd7a:91c2:4e8b:#{rem(sequence, 65_536)}::/64"
    }

    Repo.insert!(struct(Cluster, Map.merge(defaults, attrs)))
  end

  defp insert_node!(cluster) do
    sequence = System.unique_integer([:positive, :monotonic])
    public_key = Base.encode64(<<rem(sequence, 256), :binary.copy(<<0>>, 31)::binary>>)

    Repo.insert!(%Node{
      id: Ecto.UUID.generate(),
      cluster_id: cluster.id,
      vpn_host_id: Ecto.UUID.generate(),
      version: "edge-1.0.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9586,
      http_proxy_port: 8080,
      socks5_proxy_port: 1080,
      api_token: Ecto.UUID.generate(),
      proxy_password: "proxy-#{sequence}",
      ingress_public_key: public_key
    })
  end

  defp insert_alias!(cluster, node, name) do
    Repo.insert!(%Alias{
      id: Ecto.UUID.generate(),
      name: name,
      node_id: node.id,
      cluster_id: cluster.id
    })
  end

  test "combines cluster, node, and name filters while excluding retired clusters" do
    active_cluster = insert_cluster!("prod-east")
    other_cluster = insert_cluster!("staging")
    retired_cluster = insert_cluster!("prod-retired", %{deleted_at: ~U[2026-01-01 00:00:00Z]})

    target_node = insert_node!(active_cluster)
    other_node = insert_node!(other_cluster)
    retired_node = insert_node!(retired_cluster)

    target_alias = insert_alias!(active_cluster, target_node, "edge-api")
    _name_mismatch = insert_alias!(active_cluster, target_node, "db-primary")
    _cluster_mismatch = insert_alias!(other_cluster, other_node, "edge-staging")
    _retired_match = insert_alias!(retired_cluster, retired_node, "edge-retired")

    assert {:ok, {[alias_record], _meta}} =
             AliasResources.list(%{
               "cluster_name" => "prod*",
               "node_id__in" => target_node.id,
               "name" => "edge-*"
             })

    assert alias_record.id == target_alias.id
    assert alias_record.cluster.name == active_cluster.name
  end
end
