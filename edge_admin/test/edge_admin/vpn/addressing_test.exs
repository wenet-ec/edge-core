# edge_admin/test/edge_admin/vpn/addressing_test.exs
defmodule EdgeAdmin.Vpn.AddressingTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn.Addressing, as: VpnAddressing

  # ---------------------------------------------------------------------------
  # parse_ipv4/1
  # ---------------------------------------------------------------------------

  describe "parse_ipv4/1" do
    test "valid address" do
      assert VpnAddressing.parse_ipv4("192.168.1.1") == {:ok, {192, 168, 1, 1}}
    end

    test "all zeros" do
      assert VpnAddressing.parse_ipv4("0.0.0.0") == {:ok, {0, 0, 0, 0}}
    end

    test "all 255s" do
      assert VpnAddressing.parse_ipv4("255.255.255.255") == {:ok, {255, 255, 255, 255}}
    end

    test "CGNAT address" do
      assert VpnAddressing.parse_ipv4("100.64.0.1") == {:ok, {100, 64, 0, 1}}
    end

    test "error on octet above 255" do
      assert {:error, _} = VpnAddressing.parse_ipv4("256.0.0.1")
    end

    test "error on negative octet" do
      assert {:error, _} = VpnAddressing.parse_ipv4("-1.0.0.1")
    end

    test "error on too few octets" do
      assert {:error, _} = VpnAddressing.parse_ipv4("192.168.1")
    end

    test "error on too many octets" do
      assert {:error, _} = VpnAddressing.parse_ipv4("192.168.1.1.1")
    end

    test "error on non-numeric octet" do
      assert {:error, _} = VpnAddressing.parse_ipv4("192.168.one.1")
    end

    test "error on empty string" do
      assert {:error, _} = VpnAddressing.parse_ipv4("")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_cidr/1
  # ---------------------------------------------------------------------------

  describe "parse_cidr/1" do
    test "valid /24" do
      assert VpnAddressing.parse_cidr("10.0.0.0/24") == {:ok, {{10, 0, 0, 0}, 24}}
    end

    test "valid /10 (CGNAT)" do
      assert VpnAddressing.parse_cidr("100.64.0.0/10") == {:ok, {{100, 64, 0, 0}, 10}}
    end

    test "valid /0" do
      assert VpnAddressing.parse_cidr("0.0.0.0/0") == {:ok, {{0, 0, 0, 0}, 0}}
    end

    test "valid /32" do
      assert VpnAddressing.parse_cidr("192.168.1.1/32") == {:ok, {{192, 168, 1, 1}, 32}}
    end

    test "error on missing prefix" do
      assert {:error, _} = VpnAddressing.parse_cidr("10.0.0.0")
    end

    test "error on prefix above 32" do
      assert {:error, _} = VpnAddressing.parse_cidr("10.0.0.0/33")
    end

    test "error on negative prefix" do
      assert {:error, _} = VpnAddressing.parse_cidr("10.0.0.0/-1")
    end

    test "error on non-numeric prefix" do
      assert {:error, _} = VpnAddressing.parse_cidr("10.0.0.0/abc")
    end

    test "error on invalid IP" do
      assert {:error, _} = VpnAddressing.parse_cidr("invalid/24")
    end

    test "error on empty string" do
      assert {:error, _} = VpnAddressing.parse_cidr("")
    end
  end

  # ---------------------------------------------------------------------------
  # usable_ipv4_capacity/1
  # ---------------------------------------------------------------------------

  describe "usable_ipv4_capacity/1" do
    test "uses the same network-address exclusion as Netmaker" do
      assert VpnAddressing.usable_ipv4_capacity(24) == 255
    end

    test "returns zero for a /32 network" do
      assert VpnAddressing.usable_ipv4_capacity(32) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # find_available_subnet/3
  # ---------------------------------------------------------------------------

  describe "find_available_subnet/3" do
    test "returns first subnet when none are taken" do
      result = VpnAddressing.find_available_subnet("100.64.0.0/10", 24, [])
      assert result == "100.64.0.0/24"
    end

    test "skips taken subnets and returns next available" do
      existing = ["100.64.0.0/24", "100.64.1.0/24"]
      result = VpnAddressing.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == "100.64.2.0/24"
    end

    test "returns nil when invalid base CIDR" do
      result = VpnAddressing.find_available_subnet("invalid", 24, [])
      assert result == nil
    end

    test "skips all taken and finds gap" do
      # Skip 0 and 2, return 1
      existing = ["100.64.0.0/24", "100.64.2.0/24"]
      result = VpnAddressing.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == "100.64.1.0/24"
    end

    test "skips /24s contained within an existing wider /16, falls past the /16" do
      # 100.64.0.0/16 contains 100.64.0.0/24 .. 100.64.255.0/24 (256 /24s).
      # The /10 pool covers 100.64.0.0 .. 100.127.255.255 (16_384 /24s), so the
      # first /24 outside the existing /16 is 100.65.0.0/24.
      existing = ["100.64.0.0/16"]
      result = VpnAddressing.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == "100.65.0.0/24"
    end

    test "returns nil when the entire /10 pool is blocked by a wider /10" do
      existing = ["100.64.0.0/10"]
      assert VpnAddressing.find_available_subnet("100.64.0.0/10", 24, existing) == nil
    end

    test "skips /24 that overlaps a wider /8" do
      existing = ["100.0.0.0/8"]
      result = VpnAddressing.find_available_subnet("100.64.0.0/10", 24, existing)
      assert result == nil
    end
  end

  describe "IPv6 CIDR utilities" do
    test "parses a compressed IPv6 CIDR" do
      assert {:ok, {{0xFD7A, 0x91C2, 0x4E8B, 0, 0, 0, 0, 0}, 48}} =
               VpnAddressing.parse_ipv6_cidr("fd7a:91c2:4e8b::/48")
    end

    test "detects IPv6 overlap in either direction" do
      assert VpnAddressing.ipv6_cidrs_overlap?("fd7a:91c2:4e8b:1::/64", ["fd7a:91c2:4e8b::/48"])
      assert VpnAddressing.ipv6_cidrs_overlap?("fd7a:91c2:4e8b::/48", ["fd7a:91c2:4e8b:1::/64"])
      refute VpnAddressing.ipv6_cidrs_overlap?("fd7a:91c2:4e8c::/48", ["fd7a:91c2:4e8b::/48"])
    end

    test "allocates the first free /64 from a ULA /48" do
      assert VpnAddressing.find_available_ipv6_subnet("fd7a:91c2:4e8b::/48", 64, ["fd7a:91c2:4e8b::/64"]) ==
               "fd7a:91c2:4e8b:1::/64"
    end
  end

  # ---------------------------------------------------------------------------
  # cidrs_overlap?/2
  # ---------------------------------------------------------------------------

  describe "cidrs_overlap?/2" do
    test "identical ranges overlap" do
      assert VpnAddressing.cidrs_overlap?("100.64.1.0/24", ["100.64.1.0/24"])
    end

    test "narrower range inside wider range overlaps" do
      # /24 is fully inside the /16
      assert VpnAddressing.cidrs_overlap?("100.64.1.0/24", ["100.64.0.0/16"])
    end

    test "wider range containing narrower range overlaps" do
      # /16 contains the existing /24's network address
      assert VpnAddressing.cidrs_overlap?("100.64.0.0/16", ["100.64.1.0/24"])
    end

    test "completely different ranges do not overlap" do
      refute VpnAddressing.cidrs_overlap?("10.0.0.0/24", ["192.168.1.0/24"])
    end

    test "adjacent /24 ranges in same /16 do not overlap each other" do
      refute VpnAddressing.cidrs_overlap?("100.64.2.0/24", ["100.64.1.0/24"])
    end

    test "returns false when existing list is empty" do
      refute VpnAddressing.cidrs_overlap?("100.64.1.0/24", [])
    end

    test "returns false on unparseable candidate CIDR" do
      refute VpnAddressing.cidrs_overlap?("invalid", ["100.64.0.0/16"])
    end

    test "ignores unparseable entries in existing list" do
      refute VpnAddressing.cidrs_overlap?("10.0.0.0/24", ["bad-cidr", "192.168.1.0/24"])
    end

    test "detects overlap when one of many existing ranges matches" do
      existing = ["10.0.0.0/24", "10.0.1.0/24", "100.64.0.0/16"]
      assert VpnAddressing.cidrs_overlap?("100.64.5.0/24", existing)
    end

    test "returns false when none of many existing ranges overlap" do
      existing = ["10.0.0.0/24", "10.0.1.0/24", "192.168.1.0/24"]
      refute VpnAddressing.cidrs_overlap?("172.16.0.0/24", existing)
    end

    test "/32 host route inside a /24 overlaps" do
      assert VpnAddressing.cidrs_overlap?("10.0.0.5/32", ["10.0.0.0/24"])
    end

    test "/0 default route overlaps everything" do
      assert VpnAddressing.cidrs_overlap?("0.0.0.0/0", ["100.64.1.0/24"])
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
      stream = VpnAddressing.generate_subnets({100, 64, 0, 0}, 10, 24)
      assert Enum.count(stream) == 16_384
      assert Enum.at(stream, 0) == "100.64.0.0/24"
      # 100.64.0.0/10 spans 100.64.0.0 .. 100.127.255.255 — last /24 is .255.0
      assert Enum.at(stream, 16_383) == "100.127.255.0/24"
    end

    test "all generated subnets have the correct prefix" do
      subnets = VpnAddressing.generate_subnets({100, 64, 0, 0}, 10, 24)
      assert Enum.all?(subnets, &String.ends_with?(&1, "/24"))
    end

    test "starts at aligned base IP" do
      stream = VpnAddressing.generate_subnets({10, 0, 0, 0}, 10, 24)
      assert Enum.at(stream, 0) == "10.0.0.0/24"
      # /10 starting at 10.0.0.0 also covers 10.63.255.0/24 as its last /24
      assert Enum.at(stream, 16_383) == "10.63.255.0/24"
    end

    test "/16 -> /24 generates 256 subnets within the second octet" do
      subnets = {10, 0, 0, 0} |> VpnAddressing.generate_subnets(16, 24) |> Enum.to_list()
      assert length(subnets) == 256
      assert List.first(subnets) == "10.0.0.0/24"
      assert List.last(subnets) == "10.0.255.0/24"
    end

    test "/8 -> /24 generates 65_536 subnets (lazy, only count)" do
      assert {10, 0, 0, 0} |> VpnAddressing.generate_subnets(8, 24) |> Enum.count() == 65_536
    end

    test "/8 -> /24 first and last subnet wrap correctly" do
      stream = VpnAddressing.generate_subnets({10, 0, 0, 0}, 8, 24)
      assert Enum.at(stream, 0) == "10.0.0.0/24"
      assert Enum.at(stream, 255) == "10.0.255.0/24"
      assert Enum.at(stream, 256) == "10.1.0.0/24"
      assert Enum.at(stream, 65_535) == "10.255.255.0/24"
    end

    test "/10 -> /28 generates 2^18 subnets" do
      assert {100, 64, 0, 0} |> VpnAddressing.generate_subnets(10, 28) |> Enum.count() == 262_144
    end

    test "/10 -> /28 first subnets step by 16 in the host octet" do
      stream = VpnAddressing.generate_subnets({100, 64, 0, 0}, 10, 28)
      assert Enum.at(stream, 0) == "100.64.0.0/28"
      assert Enum.at(stream, 1) == "100.64.0.16/28"
      assert Enum.at(stream, 15) == "100.64.0.240/28"
      assert Enum.at(stream, 16) == "100.64.1.0/28"
    end

    test "/24 -> /24 yields exactly the aligned base" do
      assert {192, 168, 1, 0} |> VpnAddressing.generate_subnets(24, 24) |> Enum.to_list() ==
               ["192.168.1.0/24"]
    end

    test "misaligned base is realigned to its prefix boundary" do
      # 100.64.5.0 with a /10 mask aligns to 100.64.0.0 (since 64 & 0xC0 == 64)
      subnets = {100, 64, 5, 0} |> VpnAddressing.generate_subnets(10, 24) |> Enum.to_list()
      assert length(subnets) == 16_384
      assert List.first(subnets) == "100.64.0.0/24"
      assert List.last(subnets) == "100.127.255.0/24"
    end

    test "misaligned base with non-aligned second octet realigns correctly" do
      # 100.100.5.0 with /10: second octet 100 = 0x64, masked with 0xC0 = 0x40 = 64.
      # So this realigns to 100.64.0.0, same span as the canonical pool.
      subnets = {100, 100, 5, 0} |> VpnAddressing.generate_subnets(10, 24) |> Enum.to_list()
      assert List.first(subnets) == "100.64.0.0/24"
      assert List.last(subnets) == "100.127.255.0/24"
    end

    test "returns a Stream (lazy)" do
      # Should not blow up memory; we never force the whole thing.
      stream = VpnAddressing.generate_subnets({10, 0, 0, 0}, 8, 32)
      assert Enum.at(stream, 0) == "10.0.0.0/32"
      assert Enum.at(stream, 1) == "10.0.0.1/32"
    end

    test "raises when target_prefix < base_prefix" do
      assert_raise ArgumentError, ~r/target_prefix \(8\) must be >= base_prefix \(10\)/, fn ->
        VpnAddressing.generate_subnets({100, 64, 0, 0}, 10, 8)
      end
    end

    test "raises when base_prefix is out of range" do
      assert_raise ArgumentError, ~r/base_prefix must be in 0\.\.32/, fn ->
        VpnAddressing.generate_subnets({100, 64, 0, 0}, 33, 24)
      end

      assert_raise ArgumentError, ~r/base_prefix must be in 0\.\.32/, fn ->
        VpnAddressing.generate_subnets({100, 64, 0, 0}, -1, 24)
      end
    end

    test "raises when target_prefix is out of range" do
      assert_raise ArgumentError, ~r/target_prefix must be in 0\.\.32/, fn ->
        VpnAddressing.generate_subnets({100, 64, 0, 0}, 10, 33)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # find_available_subnet/3 — non-default pool shapes (regression for the old
  # `/10 → /24` hardcoded path)
  # ---------------------------------------------------------------------------

  describe "find_available_subnet/3 with non-default pools" do
    test "/16 pool returns the first /24 inside it" do
      assert VpnAddressing.find_available_subnet("10.0.0.0/16", 24, []) == "10.0.0.0/24"
    end

    test "/16 pool skips taken /24s" do
      assert VpnAddressing.find_available_subnet("10.0.0.0/16", 24, ["10.0.0.0/24", "10.0.1.0/24"]) ==
               "10.0.2.0/24"
    end

    test "/8 pool returns first /24, skipping a wider overlap" do
      assert VpnAddressing.find_available_subnet("10.0.0.0/8", 24, ["10.0.0.0/16"]) == "10.1.0.0/24"
    end

    test "/10 pool with /28 target returns first /28 and skips taken /28s" do
      assert VpnAddressing.find_available_subnet("100.64.0.0/10", 28, ["100.64.0.0/28"]) ==
               "100.64.0.16/28"
    end
  end
end
