# edge_admin/test/edge_admin/nodes/schemas/alias_test.exs
defmodule EdgeAdmin.Nodes.Schemas.AliasTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster

  defp fake_cluster(overrides \\ %{}) do
    Map.merge(%Cluster{id: "cluster-uuid-1", name: "prod", ipv4_range: "100.64.1.0/24"}, overrides)
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

  # ---------------------------------------------------------------------------
  # vpn_hostname/1
  # ---------------------------------------------------------------------------

  describe "vpn_hostname/1" do
    test "returns node-{name}.cluster-{cluster_name}.nm.internal" do
      alias_record = fake_alias(%{name: "web", cluster: fake_cluster(%{name: "prod"})})
      assert Alias.vpn_hostname(alias_record) == "node-web.cluster-prod.nm.internal"
    end

    test "uses alias name not node id" do
      alias_record = fake_alias(%{name: "my-service"})
      assert Alias.vpn_hostname(alias_record) =~ "node-my-service"
    end

    test "uses cluster name from preloaded cluster" do
      alias_record = fake_alias(%{name: "web", cluster: fake_cluster(%{name: "staging"})})
      assert Alias.vpn_hostname(alias_record) =~ "cluster-staging"
    end

    test "always starts with node-" do
      assert String.starts_with?(Alias.vpn_hostname(fake_alias()), "node-")
    end

    test "ends with configured VPN domain (nm.internal)" do
      assert String.ends_with?(Alias.vpn_hostname(fake_alias()), ".nm.internal")
    end

    test "changes when alias name changes" do
      alias_web = fake_alias(%{name: "web"})
      alias_api = fake_alias(%{name: "api"})
      refute Alias.vpn_hostname(alias_web) == Alias.vpn_hostname(alias_api)
    end

    test "changes when cluster name changes" do
      alias_prod = fake_alias(%{cluster: fake_cluster(%{name: "prod"})})
      alias_dev = fake_alias(%{cluster: fake_cluster(%{name: "dev"})})
      refute Alias.vpn_hostname(alias_prod) == Alias.vpn_hostname(alias_dev)
    end
  end

  # ---------------------------------------------------------------------------
  # netmaker_dns_name/1
  # ---------------------------------------------------------------------------

  describe "netmaker_dns_name/1" do
    test "returns node-{name}.cluster-{cluster_name} (no domain suffix)" do
      alias_record = fake_alias(%{name: "web", cluster: fake_cluster(%{name: "prod"})})
      assert Alias.netmaker_dns_name(alias_record) == "node-web.cluster-prod"
    end

    test "does not include the nm.internal suffix" do
      refute Alias.netmaker_dns_name(fake_alias()) =~ ".nm.internal"
    end

    test "is a prefix of the vpn_hostname" do
      alias_record = fake_alias()
      assert String.starts_with?(Alias.vpn_hostname(alias_record), Alias.netmaker_dns_name(alias_record))
    end

    test "uses alias name not node id" do
      alias_record = fake_alias(%{name: "my-service"})
      assert Alias.netmaker_dns_name(alias_record) =~ "node-my-service"
    end

    test "uses cluster name from preloaded cluster" do
      alias_record = fake_alias(%{cluster: fake_cluster(%{name: "staging"})})
      assert Alias.netmaker_dns_name(alias_record) =~ "cluster-staging"
    end
  end
end
