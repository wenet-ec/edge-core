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

    test "skips /24s contained within an existing wider /16, falls past the /16" do
      # 100.64.0.0/16 contains 100.64.0.0/24 .. 100.64.255.0/24 (256 /24s).
      # The /10 pool covers 100.64.0.0 .. 100.127.255.255 (16_384 /24s), so the
      # first /24 outside the existing /16 is 100.65.0.0/24.
      existing = ["100.64.0.0/16"]
      result = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == "100.65.0.0/24"
    end

    test "returns nil when the entire /10 pool is blocked by a wider /10" do
      existing = ["100.64.0.0/10"]
      assert Vpn.find_available_subnet("100.64.0.0/10", 24, existing) == nil
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
    test "generates 16_384 /24 subnets from a /10 base (full /10 coverage)" do
      # A /10 contains 2^(24-10) = 16_384 distinct /24s, not 256. The previous
      # implementation hardcoded a single second-octet, walking only the third
      # octet (256 /24s) — that bug is what this rewrite fixes.
      stream = Vpn.generate_subnets({100, 64, 0, 0}, 10, 24)
      assert Enum.count(stream) == 16_384
      assert Enum.at(stream, 0) == "100.64.0.0/24"
      # 100.64.0.0/10 spans 100.64.0.0 .. 100.127.255.255 — last /24 is .255.0
      assert Enum.at(stream, 16_383) == "100.127.255.0/24"
    end

    test "all generated subnets have the correct prefix" do
      subnets = Vpn.generate_subnets({100, 64, 0, 0}, 10, 24)
      assert Enum.all?(subnets, &String.ends_with?(&1, "/24"))
    end

    test "starts at aligned base IP" do
      stream = Vpn.generate_subnets({10, 0, 0, 0}, 10, 24)
      assert Enum.at(stream, 0) == "10.0.0.0/24"
      # /10 starting at 10.0.0.0 also covers 10.63.255.0/24 as its last /24
      assert Enum.at(stream, 16_383) == "10.63.255.0/24"
    end

    test "/16 -> /24 generates 256 subnets within the second octet" do
      subnets = {10, 0, 0, 0} |> Vpn.generate_subnets(16, 24) |> Enum.to_list()
      assert length(subnets) == 256
      assert List.first(subnets) == "10.0.0.0/24"
      assert List.last(subnets) == "10.0.255.0/24"
    end

    test "/8 -> /24 generates 65_536 subnets (lazy, only count)" do
      assert {10, 0, 0, 0} |> Vpn.generate_subnets(8, 24) |> Enum.count() == 65_536
    end

    test "/8 -> /24 first and last subnet wrap correctly" do
      stream = Vpn.generate_subnets({10, 0, 0, 0}, 8, 24)
      assert Enum.at(stream, 0) == "10.0.0.0/24"
      assert Enum.at(stream, 255) == "10.0.255.0/24"
      assert Enum.at(stream, 256) == "10.1.0.0/24"
      assert Enum.at(stream, 65_535) == "10.255.255.0/24"
    end

    test "/10 -> /28 generates 2^18 subnets" do
      assert {100, 64, 0, 0} |> Vpn.generate_subnets(10, 28) |> Enum.count() == 262_144
    end

    test "/10 -> /28 first subnets step by 16 in the host octet" do
      stream = Vpn.generate_subnets({100, 64, 0, 0}, 10, 28)
      assert Enum.at(stream, 0) == "100.64.0.0/28"
      assert Enum.at(stream, 1) == "100.64.0.16/28"
      assert Enum.at(stream, 15) == "100.64.0.240/28"
      assert Enum.at(stream, 16) == "100.64.1.0/28"
    end

    test "/24 -> /24 yields exactly the aligned base" do
      assert {192, 168, 1, 0} |> Vpn.generate_subnets(24, 24) |> Enum.to_list() ==
               ["192.168.1.0/24"]
    end

    test "misaligned base is realigned to its prefix boundary" do
      # 100.64.5.0 with a /10 mask aligns to 100.64.0.0 (since 64 & 0xC0 == 64)
      subnets = {100, 64, 5, 0} |> Vpn.generate_subnets(10, 24) |> Enum.to_list()
      assert length(subnets) == 16_384
      assert List.first(subnets) == "100.64.0.0/24"
      assert List.last(subnets) == "100.127.255.0/24"
    end

    test "misaligned base with non-aligned second octet realigns correctly" do
      # 100.100.5.0 with /10: second octet 100 = 0x64, masked with 0xC0 = 0x40 = 64.
      # So this realigns to 100.64.0.0, same span as the canonical pool.
      subnets = {100, 100, 5, 0} |> Vpn.generate_subnets(10, 24) |> Enum.to_list()
      assert List.first(subnets) == "100.64.0.0/24"
      assert List.last(subnets) == "100.127.255.0/24"
    end

    test "returns a Stream (lazy)" do
      # Should not blow up memory; we never force the whole thing.
      stream = Vpn.generate_subnets({10, 0, 0, 0}, 8, 32)
      assert Enum.at(stream, 0) == "10.0.0.0/32"
      assert Enum.at(stream, 1) == "10.0.0.1/32"
    end

    test "raises when target_prefix < base_prefix" do
      assert_raise ArgumentError, ~r/target_prefix \(8\) must be >= base_prefix \(10\)/, fn ->
        Vpn.generate_subnets({100, 64, 0, 0}, 10, 8)
      end
    end

    test "raises when base_prefix is out of range" do
      assert_raise ArgumentError, ~r/base_prefix must be in 0\.\.32/, fn ->
        Vpn.generate_subnets({100, 64, 0, 0}, 33, 24)
      end

      assert_raise ArgumentError, ~r/base_prefix must be in 0\.\.32/, fn ->
        Vpn.generate_subnets({100, 64, 0, 0}, -1, 24)
      end
    end

    test "raises when target_prefix is out of range" do
      assert_raise ArgumentError, ~r/target_prefix must be in 0\.\.32/, fn ->
        Vpn.generate_subnets({100, 64, 0, 0}, 10, 33)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # find_available_subnet/3 — non-default pool shapes (regression for the old
  # `/10 → /24` hardcoded path)
  # ---------------------------------------------------------------------------

  describe "find_available_subnet/3 with non-default pools" do
    test "/16 pool returns the first /24 inside it" do
      assert Vpn.find_available_subnet("10.0.0.0/16", 24, []) == "10.0.0.0/24"
    end

    test "/16 pool skips taken /24s" do
      assert Vpn.find_available_subnet("10.0.0.0/16", 24, ["10.0.0.0/24", "10.0.1.0/24"]) ==
               "10.0.2.0/24"
    end

    test "/8 pool returns first /24, skipping a wider overlap" do
      assert Vpn.find_available_subnet("10.0.0.0/8", 24, ["10.0.0.0/16"]) == "10.1.0.0/24"
    end

    test "/10 pool with /28 target returns first /28 and skips taken /28s" do
      assert Vpn.find_available_subnet("100.64.0.0/10", 28, ["100.64.0.0/28"]) ==
               "100.64.0.16/28"
    end
  end

  # ---------------------------------------------------------------------------
  # select_host_id/3
  # ---------------------------------------------------------------------------

  describe "select_host_id/3" do
    test "returns nil when no host matches hostname" do
      assert Vpn.select_host_id([], [], "node-abc") == nil
    end

    test "returns the only matching host" do
      hosts = [%{"id" => "h1", "name" => "node-abc"}]

      assert Vpn.select_host_id(hosts, [], "node-abc") == "h1"
    end

    test "prefers connected host when duplicate hostnames exist" do
      hosts = [
        %{"id" => "stale", "name" => "node-abc"},
        %{"id" => "live", "name" => "node-abc"}
      ]

      nodes = [
        %{
          "hostid" => "stale",
          "connected" => false,
          "lastmodified" => 100,
          "lastcheckin" => 100,
          "lastpeerupdate" => 100
        },
        %{"hostid" => "live", "connected" => true, "lastmodified" => 90, "lastcheckin" => 90, "lastpeerupdate" => 90}
      ]

      assert Vpn.select_host_id(hosts, nodes, "node-abc") == "live"
    end

    test "uses node recency as a tie-breaker for duplicate disconnected hosts" do
      hosts = [
        %{"id" => "old", "name" => "node-abc"},
        %{"id" => "new", "name" => "node-abc"}
      ]

      nodes = [
        %{
          "hostid" => "old",
          "connected" => false,
          "lastmodified" => 100,
          "lastcheckin" => 100,
          "lastpeerupdate" => 100
        },
        %{"hostid" => "new", "connected" => false, "lastmodified" => 200, "lastcheckin" => 150, "lastpeerupdate" => 125}
      ]

      assert Vpn.select_host_id(hosts, nodes, "node-abc") == "new"
    end
  end
end
