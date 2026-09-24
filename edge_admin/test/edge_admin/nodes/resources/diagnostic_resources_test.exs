# edge_admin/test/edge_admin/nodes/resources/diagnostic_resources_test.exs
defmodule EdgeAdmin.Nodes.Resources.DiagnosticResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Resources.DiagnosticResources
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Repo

  defp insert_node! do
    sequence = System.unique_integer([:positive, :monotonic])

    cluster =
      Repo.insert!(%Cluster{
        id: Ecto.UUID.generate(),
        name: "diagnostics-#{sequence}",
        ipv4_range: "100.64.#{rem(sequence, 200)}.0/24",
        ipv6_range: "fd7a:91c2:4e8b:#{rem(sequence, 65_536)}::/64"
      })

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

  defp insert_diagnostic!(node, updated_at) do
    Repo.insert!(%NodeDiagnostic{
      node_id: node.id,
      report: %{"overall" => "pass"},
      inserted_at: updated_at,
      updated_at: updated_at
    })
  end

  test "returns reports at the freshness cutoff and excludes older reports" do
    now = ~U[2026-02-01 12:00:00Z]
    fresh_node = insert_node!()
    stale_node = insert_node!()
    fresh = insert_diagnostic!(fresh_node, DateTime.shift(now, minute: -5))
    _stale = insert_diagnostic!(stale_node, DateTime.shift(now, second: -301))

    assert DiagnosticResources.get_recent(fresh_node.id, now).id == fresh.id
    assert DiagnosticResources.get_recent(stale_node.id, now) == nil
  end
end
