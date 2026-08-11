# edge_admin/test/edge_admin/vpn/naming_test.exs
defmodule EdgeAdmin.Vpn.NamingTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn.Naming, as: VpnNaming

  # ---------------------------------------------------------------------------
  # build_vpn_name/2
  # ---------------------------------------------------------------------------

  describe "build_vpn_name/2" do
    test "defaults to node prefix" do
      assert VpnNaming.build_vpn_name("abc123") == "node-abc123"
    end

    test "explicit node prefix" do
      assert VpnNaming.build_vpn_name("abc123", prefix: :node) == "node-abc123"
    end

    test "admin prefix" do
      assert VpnNaming.build_vpn_name("k7m3n2p9", prefix: :admin) == "admin-k7m3n2p9"
    end

    test "preserves hyphens in name" do
      assert VpnNaming.build_vpn_name("abc-def-123") == "node-abc-def-123"
    end
  end

  # ---------------------------------------------------------------------------
  # build_network_name/2
  # ---------------------------------------------------------------------------

  describe "build_network_name/2" do
    test "defaults to cluster prefix" do
      assert VpnNaming.build_network_name("prod-east") == "cluster-prod-east"
    end

    test "explicit node prefix" do
      assert VpnNaming.build_network_name("prod-east", prefix: :node) == "cluster-prod-east"
    end

    test "admin prefix" do
      assert VpnNaming.build_network_name("prod", prefix: :admin) == "admin-cluster-prod"
    end

    test "admin prefix raises on invalid suffix" do
      assert_raise ArgumentError, fn ->
        VpnNaming.build_network_name("INVALID", prefix: :admin)
      end
    end

    test "admin prefix raises when total name exceeds 32 chars" do
      # "admin-cluster-" is 14 chars, so suffix > 18 chars will exceed 32
      long_suffix = String.duplicate("a", 19)

      assert_raise ArgumentError, fn ->
        VpnNaming.build_network_name(long_suffix, prefix: :admin)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # validate_admin_cluster_suffix!/1
  # ---------------------------------------------------------------------------

  describe "validate_admin_cluster_suffix!/1" do
    test "valid simple name" do
      assert VpnNaming.validate_admin_cluster_suffix!("prod") == :ok
    end

    test "valid name with hyphens" do
      assert VpnNaming.validate_admin_cluster_suffix!("prod-east-1") == :ok
    end

    test "valid single character" do
      assert VpnNaming.validate_admin_cluster_suffix!("a") == :ok
    end

    test "valid name at max length (18 chars suffix → 32 total)" do
      suffix = String.duplicate("a", 18)
      assert VpnNaming.validate_admin_cluster_suffix!(suffix) == :ok
    end

    test "raises on uppercase" do
      assert_raise ArgumentError, fn ->
        VpnNaming.validate_admin_cluster_suffix!("Prod")
      end
    end

    test "raises on leading hyphen" do
      assert_raise ArgumentError, fn ->
        VpnNaming.validate_admin_cluster_suffix!("-prod")
      end
    end

    test "raises on trailing hyphen" do
      assert_raise ArgumentError, fn ->
        VpnNaming.validate_admin_cluster_suffix!("prod-")
      end
    end

    test "raises on special characters" do
      assert_raise ArgumentError, fn ->
        VpnNaming.validate_admin_cluster_suffix!("prod_east")
      end
    end

    test "raises on spaces" do
      assert_raise ArgumentError, fn ->
        VpnNaming.validate_admin_cluster_suffix!("prod east")
      end
    end

    test "raises when total length exceeds 32 chars" do
      # "admin-cluster-" = 14 chars, suffix of 19 → total 33
      suffix = String.duplicate("a", 19)

      assert_raise ArgumentError, fn ->
        VpnNaming.validate_admin_cluster_suffix!(suffix)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # validate_network_name/1
  # ---------------------------------------------------------------------------

  describe "validate_network_name/1" do
    test "valid simple name" do
      assert VpnNaming.validate_network_name("cluster-prod") == :ok
    end

    test "valid name with numbers" do
      assert VpnNaming.validate_network_name("cluster-01") == :ok
    end

    test "valid name at exactly 32 chars" do
      name = String.duplicate("a", 32)
      assert VpnNaming.validate_network_name(name) == :ok
    end

    test "error when name exceeds 32 chars" do
      name = String.duplicate("a", 33)
      assert {:error, _msg} = VpnNaming.validate_network_name(name)
    end

    test "error on uppercase" do
      assert {:error, _msg} = VpnNaming.validate_network_name("Cluster-Prod")
    end

    test "error on leading hyphen" do
      assert {:error, _msg} = VpnNaming.validate_network_name("-cluster")
    end

    test "error on trailing hyphen" do
      assert {:error, _msg} = VpnNaming.validate_network_name("cluster-")
    end

    test "error on underscore" do
      assert {:error, _msg} = VpnNaming.validate_network_name("cluster_prod")
    end
  end

  # ---------------------------------------------------------------------------
  # build_vpn_domain/2
  # ---------------------------------------------------------------------------

  describe "build_vpn_domain/2" do
    test "combines network and default domain from config" do
      # test.exs sets edge_vpn_default_domain to "nm.internal"
      assert VpnNaming.build_vpn_domain("cluster-xyz") == "cluster-xyz.nm.internal"
    end

    test "uses explicit domain argument over config" do
      assert VpnNaming.build_vpn_domain("cluster-xyz", "custom.vpn") == "cluster-xyz.custom.vpn"
    end

    test "empty domain returns just the network name" do
      assert VpnNaming.build_vpn_domain("cluster-xyz", "") == "cluster-xyz"
    end
  end

  # ---------------------------------------------------------------------------
  # build_vpn_hostname/3
  # ---------------------------------------------------------------------------

  describe "build_vpn_hostname/3" do
    test "builds FQDN from host, network and default domain" do
      assert VpnNaming.build_vpn_hostname("node-abc", "cluster-xyz") ==
               "node-abc.cluster-xyz.nm.internal"
    end

    test "uses explicit domain" do
      assert VpnNaming.build_vpn_hostname("node-abc", "cluster-xyz", "custom.domain") ==
               "node-abc.cluster-xyz.custom.domain"
    end

    test "empty domain produces host.network" do
      assert VpnNaming.build_vpn_hostname("node-abc", "cluster-xyz", "") ==
               "node-abc.cluster-xyz"
    end
  end

  # ---------------------------------------------------------------------------
  # build_admin_erlang_node_name/1
  # ---------------------------------------------------------------------------

  describe "build_admin_erlang_node_name/1" do
    test "produces an atom in admin@hostname format" do
      result = VpnNaming.build_admin_erlang_node_name("node-abc.cluster-xyz.nm.internal")
      assert result == :"admin@node-abc.cluster-xyz.nm.internal"
      assert is_atom(result)
    end
  end
end
