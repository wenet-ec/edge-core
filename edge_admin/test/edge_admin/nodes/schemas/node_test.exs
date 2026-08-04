# edge_admin/test/edge_admin/nodes/schemas/node_test.exs
defmodule EdgeAdmin.Nodes.Schemas.NodeTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Schemas.NodeMetricsCache
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(
      %Cluster{
        id: "cluster-uuid-1",
        name: "prod",
        ipv4_range: "100.64.1.0/24",
        ipv6_range: "fd7a:91c2:4e8b:1::/64"
      },
      overrides
    )
  end

  defp fake_node(overrides \\ %{}) do
    Map.merge(
      %Node{
        id: Uniq.UUID.uuid7(),
        cluster: fake_cluster()
      },
      overrides
    )
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: Uniq.UUID.uuid7(),
        cluster_id: "11111111-2222-3333-4444-555555555555",
        netmaker_host_id: "22222222-3333-4444-5555-666666666666",
        status: :healthy,
        http_port: 44_000,
        ssh_port: 40_022,
        host_metrics_port: 49_100,
        wireguard_metrics_port: 49_586,
        http_proxy_port: 43_128,
        socks5_proxy_port: 41_080,
        api_token: "node-api-token",
        proxy_password: "node-proxy-password",
        version: "1.0.0",
        self_update_enabled: false
      },

      # ---------------------------------------------------------------------------
      # changeset/2
      # ---------------------------------------------------------------------------

      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  describe "changeset/2" do
    test "accepts valid registration attributes" do
      assert Node.changeset(%Node{}, valid_attrs()).valid?
    end

    test "accepts a nil recovery key" do
      assert Node.changeset(%Node{}, valid_attrs(%{recovery_key: nil})).valid?
    end

    test "accepts a recovery key" do
      assert Node.changeset(%Node{}, valid_attrs(%{recovery_key: "recovery-key"})).valid?
    end

    test "requires a Netmaker host ID" do
      changeset = Node.changeset(%Node{}, Map.delete(valid_attrs(), :netmaker_host_id))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).netmaker_host_id
    end

    test "accepts a valid UUID from another version" do
      assert Node.changeset(%Node{}, valid_attrs(%{id: Ecto.UUID.generate()})).valid?
    end

    test "rejects a malformed UUID" do
      changeset = Node.changeset(%Node{}, valid_attrs(%{id: "not-a-uuid"}))

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).id
    end

    test "accepts every configured service port at both inclusive boundaries" do
      for field <- [
            :http_port,
            :ssh_port,
            :host_metrics_port,
            :wireguard_metrics_port,
            :http_proxy_port,
            :socks5_proxy_port
          ],
          port <- [1, 65_535] do
        assert Node.changeset(%Node{}, valid_attrs(%{field => port})).valid?,
               "expected #{field}=#{port} to be valid"
      end
    end

    test "rejects every configured service port outside the TCP/UDP range" do
      for field <- [
            :http_port,
            :ssh_port,
            :host_metrics_port,
            :wireguard_metrics_port,
            :http_proxy_port,
            :socks5_proxy_port
          ],
          port <- [0, 65_536] do
        changeset = Node.changeset(%Node{}, valid_attrs(%{field => port}))

        # ---------------------------------------------------------------------------
        # associations
        # ---------------------------------------------------------------------------

        refute changeset.valid?, "expected #{field}=#{port} to be invalid"
        assert "must be between 1 and 65535" in errors_on(changeset)[field]
      end
    end
  end

  describe "associations" do
    test "maps the latest diagnostic as a one-to-one association" do
      association = Node.__schema__(:association, :node_diagnostic)

      assert association.cardinality == :one
      assert association.related == NodeDiagnostic
      assert association.on_delete == :delete_all
    end

    test "maps one metrics cache per supported metrics type" do
      for {association_name, metrics_type} <- [
            {:host_metrics_cache, "host"},
            {:agent_metrics_cache, "agent"},
            {:wireguard_metrics_cache, "wireguard"}
          ] do
        association = Node.__schema__(:association, association_name)

        assert association.cardinality == :one
        assert association.related == NodeMetricsCache
        assert association.where == [metrics_type: metrics_type]
        assert association.on_delete == :delete_all
      end
    end

    test "maps SSH public keys through SSH usernames" do
      association = Node.__schema__(:association, :ssh_public_keys)

      assert association.cardinality == :many
      assert association.through == [:ssh_usernames, :ssh_public_keys]

      through_association = SshPublicKey.__schema__(:association, :ssh_username)
      # ---------------------------------------------------------------------------
      # node_name/1
      # ---------------------------------------------------------------------------
      assert through_association.related == EdgeAdmin.Ssh.Schemas.SshUsername
    end
  end

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

  describe "mdns_hostname/1" do
    # ---------------------------------------------------------------------------
    # mdns_hostname/1
    # ---------------------------------------------------------------------------
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

  describe "hostname distinctness" do
    test "vpn_hostname and mdns_hostname are different" do
      node = fake_node()
      refute Node.vpn_hostname(node) == Node.mdns_hostname(node)
    end

    # ---------------------------------------------------------------------------
    # hostname distinctness
    # ---------------------------------------------------------------------------
  end
end
