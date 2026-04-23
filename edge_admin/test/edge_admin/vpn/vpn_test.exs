# edge_admin/test/edge_admin/vpn_test.exs
defmodule EdgeAdmin.VpnTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn

  # ---------------------------------------------------------------------------
  # build_vpn_name/2
  # ---------------------------------------------------------------------------

  describe "build_vpn_name/2" do
    test "defaults to node prefix" do
      assert Vpn.build_vpn_name("abc123") == "node-abc123"
    end

    test "explicit node prefix" do
      assert Vpn.build_vpn_name("abc123", prefix: :node) == "node-abc123"
    end

    test "admin prefix" do
      assert Vpn.build_vpn_name("k7m3n2p9", prefix: :admin) == "admin-k7m3n2p9"
    end

    test "preserves hyphens in name" do
      assert Vpn.build_vpn_name("abc-def-123") == "node-abc-def-123"
    end
  end

  # ---------------------------------------------------------------------------
  # build_network_name/2
  # ---------------------------------------------------------------------------

  describe "build_network_name/2" do
    test "defaults to cluster prefix" do
      assert Vpn.build_network_name("prod-east") == "cluster-prod-east"
    end

    test "explicit node prefix" do
      assert Vpn.build_network_name("prod-east", prefix: :node) == "cluster-prod-east"
    end

    test "admin prefix" do
      assert Vpn.build_network_name("prod", prefix: :admin) == "admin-cluster-prod"
    end

    test "admin prefix raises on invalid suffix" do
      assert_raise ArgumentError, fn ->
        Vpn.build_network_name("INVALID", prefix: :admin)
      end
    end

    test "admin prefix raises when total name exceeds 32 chars" do
      # "admin-cluster-" is 14 chars, so suffix > 18 chars will exceed 32
      long_suffix = String.duplicate("a", 19)

      assert_raise ArgumentError, fn ->
        Vpn.build_network_name(long_suffix, prefix: :admin)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # validate_admin_cluster_suffix!/1
  # ---------------------------------------------------------------------------

  describe "validate_admin_cluster_suffix!/1" do
    test "valid simple name" do
      assert Vpn.validate_admin_cluster_suffix!("prod") == :ok
    end

    test "valid name with hyphens" do
      assert Vpn.validate_admin_cluster_suffix!("prod-east-1") == :ok
    end

    test "valid single character" do
      assert Vpn.validate_admin_cluster_suffix!("a") == :ok
    end

    test "valid name at max length (18 chars suffix → 32 total)" do
      suffix = String.duplicate("a", 18)
      assert Vpn.validate_admin_cluster_suffix!(suffix) == :ok
    end

    test "raises on uppercase" do
      assert_raise ArgumentError, fn ->
        Vpn.validate_admin_cluster_suffix!("Prod")
      end
    end

    test "raises on leading hyphen" do
      assert_raise ArgumentError, fn ->
        Vpn.validate_admin_cluster_suffix!("-prod")
      end
    end

    test "raises on trailing hyphen" do
      assert_raise ArgumentError, fn ->
        Vpn.validate_admin_cluster_suffix!("prod-")
      end
    end

    test "raises on special characters" do
      assert_raise ArgumentError, fn ->
        Vpn.validate_admin_cluster_suffix!("prod_east")
      end
    end

    test "raises on spaces" do
      assert_raise ArgumentError, fn ->
        Vpn.validate_admin_cluster_suffix!("prod east")
      end
    end

    test "raises when total length exceeds 32 chars" do
      # "admin-cluster-" = 14 chars, suffix of 19 → total 33
      suffix = String.duplicate("a", 19)

      assert_raise ArgumentError, fn ->
        Vpn.validate_admin_cluster_suffix!(suffix)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # validate_network_name/1
  # ---------------------------------------------------------------------------

  describe "validate_network_name/1" do
    test "valid simple name" do
      assert Vpn.validate_network_name("cluster-prod") == :ok
    end

    test "valid name with numbers" do
      assert Vpn.validate_network_name("cluster-01") == :ok
    end

    test "valid name at exactly 32 chars" do
      name = String.duplicate("a", 32)
      assert Vpn.validate_network_name(name) == :ok
    end

    test "error when name exceeds 32 chars" do
      name = String.duplicate("a", 33)
      assert {:error, _msg} = Vpn.validate_network_name(name)
    end

    test "error on uppercase" do
      assert {:error, _msg} = Vpn.validate_network_name("Cluster-Prod")
    end

    test "error on leading hyphen" do
      assert {:error, _msg} = Vpn.validate_network_name("-cluster")
    end

    test "error on trailing hyphen" do
      assert {:error, _msg} = Vpn.validate_network_name("cluster-")
    end

    test "error on underscore" do
      assert {:error, _msg} = Vpn.validate_network_name("cluster_prod")
    end
  end

  # ---------------------------------------------------------------------------
  # build_vpn_domain/2
  # ---------------------------------------------------------------------------

  describe "build_vpn_domain/2" do
    test "combines network and default domain from config" do
      # test.exs sets netmaker_default_domain to "nm.internal"
      assert Vpn.build_vpn_domain("cluster-xyz") == "cluster-xyz.nm.internal"
    end

    test "uses explicit domain argument over config" do
      assert Vpn.build_vpn_domain("cluster-xyz", "custom.vpn") == "cluster-xyz.custom.vpn"
    end

    test "empty domain returns just the network name" do
      assert Vpn.build_vpn_domain("cluster-xyz", "") == "cluster-xyz"
    end
  end

  # ---------------------------------------------------------------------------
  # build_vpn_hostname/3
  # ---------------------------------------------------------------------------

  describe "build_vpn_hostname/3" do
    test "builds FQDN from host, network and default domain" do
      assert Vpn.build_vpn_hostname("node-abc", "cluster-xyz") ==
               "node-abc.cluster-xyz.nm.internal"
    end

    test "uses explicit domain" do
      assert Vpn.build_vpn_hostname("node-abc", "cluster-xyz", "custom.domain") ==
               "node-abc.cluster-xyz.custom.domain"
    end

    test "empty domain produces host.network" do
      assert Vpn.build_vpn_hostname("node-abc", "cluster-xyz", "") ==
               "node-abc.cluster-xyz"
    end
  end

  # ---------------------------------------------------------------------------
  # build_admin_erlang_node_name/1
  # ---------------------------------------------------------------------------

  describe "build_admin_erlang_node_name/1" do
    test "produces an atom in admin@hostname format" do
      result = Vpn.build_admin_erlang_node_name("node-abc.cluster-xyz.nm.internal")
      assert result == :"admin@node-abc.cluster-xyz.nm.internal"
      assert is_atom(result)
    end
  end

  # ---------------------------------------------------------------------------
  # parse_ipv4/1
  # ---------------------------------------------------------------------------

  describe "parse_ipv4/1" do
    test "valid address" do
      assert Vpn.parse_ipv4("192.168.1.1") == {:ok, {192, 168, 1, 1}}
    end

    test "all zeros" do
      assert Vpn.parse_ipv4("0.0.0.0") == {:ok, {0, 0, 0, 0}}
    end

    test "all 255s" do
      assert Vpn.parse_ipv4("255.255.255.255") == {:ok, {255, 255, 255, 255}}
    end

    test "CGNAT address" do
      assert Vpn.parse_ipv4("100.64.0.1") == {:ok, {100, 64, 0, 1}}
    end

    test "error on octet above 255" do
      assert {:error, _} = Vpn.parse_ipv4("256.0.0.1")
    end

    test "error on negative octet" do
      assert {:error, _} = Vpn.parse_ipv4("-1.0.0.1")
    end

    test "error on too few octets" do
      assert {:error, _} = Vpn.parse_ipv4("192.168.1")
    end

    test "error on too many octets" do
      assert {:error, _} = Vpn.parse_ipv4("192.168.1.1.1")
    end

    test "error on non-numeric octet" do
      assert {:error, _} = Vpn.parse_ipv4("192.168.one.1")
    end

    test "error on empty string" do
      assert {:error, _} = Vpn.parse_ipv4("")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_cidr/1
  # ---------------------------------------------------------------------------

  describe "parse_cidr/1" do
    test "valid /24" do
      assert Vpn.parse_cidr("10.0.0.0/24") == {:ok, {{10, 0, 0, 0}, 24}}
    end

    test "valid /10 (CGNAT)" do
      assert Vpn.parse_cidr("100.64.0.0/10") == {:ok, {{100, 64, 0, 0}, 10}}
    end

    test "valid /0" do
      assert Vpn.parse_cidr("0.0.0.0/0") == {:ok, {{0, 0, 0, 0}, 0}}
    end

    test "valid /32" do
      assert Vpn.parse_cidr("192.168.1.1/32") == {:ok, {{192, 168, 1, 1}, 32}}
    end

    test "error on missing prefix" do
      assert {:error, _} = Vpn.parse_cidr("10.0.0.0")
    end

    test "error on prefix above 32" do
      assert {:error, _} = Vpn.parse_cidr("10.0.0.0/33")
    end

    test "error on negative prefix" do
      assert {:error, _} = Vpn.parse_cidr("10.0.0.0/-1")
    end

    test "error on non-numeric prefix" do
      assert {:error, _} = Vpn.parse_cidr("10.0.0.0/abc")
    end

    test "error on invalid IP" do
      assert {:error, _} = Vpn.parse_cidr("invalid/24")
    end

    test "error on empty string" do
      assert {:error, _} = Vpn.parse_cidr("")
    end
  end

  # ---------------------------------------------------------------------------
  # find_available_subnet/3
  # ---------------------------------------------------------------------------

  describe "find_available_subnet/3" do
    test "returns first subnet when none are taken" do
      result = Vpn.find_available_subnet("100.64.0.0/10", 24, [])
      assert result == "100.64.0.0/24"
    end

    test "skips taken subnets and returns next available" do
      existing = ["100.64.0.0/24", "100.64.1.0/24"]
      result = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == "100.64.2.0/24"
    end

    test "returns nil when invalid base CIDR" do
      result = Vpn.find_available_subnet("invalid", 24, [])
      assert result == nil
    end

    test "skips all taken and finds gap" do
      # Skip 0 and 2, return 1
      existing = ["100.64.0.0/24", "100.64.2.0/24"]
      result = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == "100.64.1.0/24"
    end

    test "skips /24 that is contained within an existing wider /16" do
      # 100.64.1.0/24 is inside 100.64.0.0/16, so it must be skipped
      existing = ["100.64.0.0/16"]
      result = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)
      # All 100.64.x.0/24 candidates fall inside the /16 — no available subnet
      assert result == nil
    end

    test "skips /24 that overlaps a wider /8" do
      existing = ["100.0.0.0/8"]
      result = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == nil
    end
  end

  # ---------------------------------------------------------------------------
  # cidrs_overlap?/2
  # ---------------------------------------------------------------------------

  describe "cidrs_overlap?/2" do
    test "identical ranges overlap" do
      assert Vpn.cidrs_overlap?("100.64.1.0/24", ["100.64.1.0/24"])
    end

    test "narrower range inside wider range overlaps" do
      # /24 is fully inside the /16
      assert Vpn.cidrs_overlap?("100.64.1.0/24", ["100.64.0.0/16"])
    end

    test "wider range containing narrower range overlaps" do
      # /16 contains the existing /24's network address
      assert Vpn.cidrs_overlap?("100.64.0.0/16", ["100.64.1.0/24"])
    end

    test "completely different ranges do not overlap" do
      refute Vpn.cidrs_overlap?("10.0.0.0/24", ["192.168.1.0/24"])
    end

    test "adjacent /24 ranges in same /16 do not overlap each other" do
      refute Vpn.cidrs_overlap?("100.64.2.0/24", ["100.64.1.0/24"])
    end

    test "returns false when existing list is empty" do
      refute Vpn.cidrs_overlap?("100.64.1.0/24", [])
    end

    test "returns false on unparseable candidate CIDR" do
      refute Vpn.cidrs_overlap?("invalid", ["100.64.0.0/16"])
    end

    test "ignores unparseable entries in existing list" do
      refute Vpn.cidrs_overlap?("10.0.0.0/24", ["bad-cidr", "192.168.1.0/24"])
    end

    test "detects overlap when one of many existing ranges matches" do
      existing = ["10.0.0.0/24", "10.0.1.0/24", "100.64.0.0/16"]
      assert Vpn.cidrs_overlap?("100.64.5.0/24", existing)
    end

    test "returns false when none of many existing ranges overlap" do
      existing = ["10.0.0.0/24", "10.0.1.0/24", "192.168.1.0/24"]
      refute Vpn.cidrs_overlap?("172.16.0.0/24", existing)
    end

    test "/32 host route inside a /24 overlaps" do
      assert Vpn.cidrs_overlap?("10.0.0.5/32", ["10.0.0.0/24"])
    end

    test "/0 default route overlaps everything" do
      assert Vpn.cidrs_overlap?("0.0.0.0/0", ["100.64.1.0/24"])
    end
  end

  # ---------------------------------------------------------------------------
  # generate_subnets/3
  # ---------------------------------------------------------------------------

  describe "generate_subnets/3" do
    test "generates 256 /24 subnets from a /10 base" do
      subnets = Vpn.generate_subnets({100, 64, 0, 0}, 10, 24)
      assert length(subnets) == 256
      assert List.first(subnets) == "100.64.0.0/24"
      assert List.last(subnets) == "100.64.255.0/24"
    end

    test "all generated subnets have the correct prefix" do
      subnets = Vpn.generate_subnets({100, 64, 0, 0}, 10, 24)
      assert Enum.all?(subnets, &String.ends_with?(&1, "/24"))
    end

    test "uses first two octets from base IP" do
      subnets = Vpn.generate_subnets({10, 0, 0, 0}, 10, 24)
      assert List.first(subnets) == "10.0.0.0/24"
      assert List.last(subnets) == "10.0.255.0/24"
    end

    test "non /10->24 combination returns single subnet fallback" do
      subnets = Vpn.generate_subnets({10, 0, 0, 0}, 16, 24)
      assert subnets == ["10.0.0.0/24"]
    end
  end
end
