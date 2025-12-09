# edge_admin/test/edge_admin/vpn_test.exs
defmodule EdgeAdmin.VpnTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn

  describe "build_dns_name/2 with prefix: :admin" do
    test "builds admin name from admin ID" do
      assert Vpn.build_dns_name("k7m3n2p9x4j6", prefix: :admin) == "admin-k7m3n2p9x4j6"
    end

    test "handles various admin ID formats" do
      assert Vpn.build_dns_name("abc123", prefix: :admin) == "admin-abc123"
      assert Vpn.build_dns_name("test-id-123", prefix: :admin) == "admin-test-id-123"
      assert Vpn.build_dns_name("x9j4p2k7m8n3", prefix: :admin) == "admin-x9j4p2k7m8n3"
    end
  end

  describe "build_network_name/2 with prefix: :admin" do
    test "builds valid admin cluster name from suffix" do
      assert Vpn.build_network_name("prod", prefix: :admin) == "admin-cluster-prod"
      assert Vpn.build_network_name("staging", prefix: :admin) == "admin-cluster-staging"
      assert Vpn.build_network_name("dev-us-west", prefix: :admin) == "admin-cluster-dev-us-west"
    end

    test "validates suffix format - lowercase alphanumeric with hyphens" do
      # Valid formats
      assert Vpn.build_network_name("prod", prefix: :admin) == "admin-cluster-prod"
      assert Vpn.build_network_name("prod-123", prefix: :admin) == "admin-cluster-prod-123"
      assert Vpn.build_network_name("123-prod", prefix: :admin) == "admin-cluster-123-prod"

      # Invalid formats - should raise
      assert_raise ArgumentError, fn ->
        Vpn.build_network_name("PROD", prefix: :admin)  # Uppercase
      end

      assert_raise ArgumentError, fn ->
        Vpn.build_network_name("prod_env", prefix: :admin)  # Underscore
      end

      assert_raise ArgumentError, fn ->
        Vpn.build_network_name("-prod", prefix: :admin)  # Leading hyphen
      end

      assert_raise ArgumentError, fn ->
        Vpn.build_network_name("prod-", prefix: :admin)  # Trailing hyphen
      end
    end

    test "validates total length does not exceed 32 characters" do
      # Valid: 32 chars total (admin-cluster- = 14 chars + 18 char suffix)
      assert Vpn.build_network_name("a23456789012345678", prefix: :admin) == "admin-cluster-a23456789012345678"

      # Invalid: 33 chars total (admin-cluster- = 14 chars + 19 char suffix)
      assert_raise ArgumentError, ~r/exceeds.*32 character limit/i, fn ->
        Vpn.build_network_name("a234567890123456789", prefix: :admin)
      end
    end
  end

  describe "build_network_name/2 with prefix: :node (default)" do
    test "builds cluster network name" do
      assert Vpn.build_network_name("prod-east", prefix: :node) == "cluster-prod-east"
      assert Vpn.build_network_name("abc123", prefix: :node) == "cluster-abc123"
      assert Vpn.build_network_name("my-cluster", prefix: :node) == "cluster-my-cluster"
    end
  end

  describe "validate_network_name/1" do
    test "validates correct network names" do
      assert Vpn.validate_network_name("admin-cluster-prod") == :ok
      assert Vpn.validate_network_name("cluster-abc123") == :ok
      assert Vpn.validate_network_name("my-network") == :ok
    end

    test "rejects network names exceeding 32 characters" do
      assert {:error, "network name exceeds 32 character limit"} =
               Vpn.validate_network_name("this-is-a-very-long-network-name-exceeding-limit")
    end

    test "rejects invalid characters" do
      assert {:error, _} = Vpn.validate_network_name("UPPERCASE")
      assert {:error, _} = Vpn.validate_network_name("has_underscore")
      assert {:error, _} = Vpn.validate_network_name("-leading-hyphen")
      assert {:error, _} = Vpn.validate_network_name("trailing-hyphen-")
    end
  end

  describe "build_hostname/3" do
    test "builds hostname with default domain" do
      assert Vpn.build_hostname("node-abc", "cluster-xyz") ==
               "node-abc.cluster-xyz.nm.internal"
    end

    test "builds hostname with custom domain" do
      assert Vpn.build_hostname("node-abc", "cluster-xyz", "custom.domain") ==
               "node-abc.cluster-xyz.custom.domain"
    end

    test "builds hostname without domain when empty string" do
      assert Vpn.build_hostname("node-abc", "cluster-xyz", "") ==
               "node-abc.cluster-xyz"
    end
  end

  describe "build_domain/2" do
    test "builds domain with default suffix" do
      assert Vpn.build_domain("cluster-xyz") == "cluster-xyz.nm.internal"
    end

    test "builds domain with custom suffix" do
      assert Vpn.build_domain("cluster-xyz", "custom.domain") ==
               "cluster-xyz.custom.domain"
    end

    test "returns network name without suffix when empty string" do
      assert Vpn.build_domain("cluster-xyz", "") == "cluster-xyz"
    end
  end

  describe "parse_cidr/1" do
    test "parses valid CIDR notation" do
      assert {:ok, {{10, 0, 0, 0}, 24}} = Vpn.parse_cidr("10.0.0.0/24")
      assert {:ok, {{192, 168, 1, 0}, 16}} = Vpn.parse_cidr("192.168.1.0/16")
      assert {:ok, {{100, 64, 0, 0}, 10}} = Vpn.parse_cidr("100.64.0.0/10")
    end

    test "rejects invalid CIDR notation" do
      assert {:error, "invalid CIDR format"} = Vpn.parse_cidr("invalid")
      assert {:error, "invalid CIDR format"} = Vpn.parse_cidr("10.0.0.0")
      assert {:error, "invalid CIDR format"} = Vpn.parse_cidr("10.0.0.0/33")
    end
  end

  describe "parse_ipv4/1" do
    test "parses valid IPv4 addresses" do
      assert {:ok, {192, 168, 1, 1}} = Vpn.parse_ipv4("192.168.1.1")
      assert {:ok, {10, 0, 0, 0}} = Vpn.parse_ipv4("10.0.0.0")
      assert {:ok, {255, 255, 255, 255}} = Vpn.parse_ipv4("255.255.255.255")
    end

    test "rejects invalid IPv4 addresses" do
      assert {:error, "invalid IPv4 address"} = Vpn.parse_ipv4("invalid")
      assert {:error, "invalid IPv4 address"} = Vpn.parse_ipv4("192.168.1")
      assert {:error, "invalid IPv4 address"} = Vpn.parse_ipv4("192.168.1.256")
      assert {:error, "invalid IPv4 address"} = Vpn.parse_ipv4("192.168.1.1.1")
    end
  end

  describe "generate_subnets/3" do
    test "generates all /24 subnets within a /10 range" do
      subnets = Vpn.generate_subnets({100, 64, 0, 0}, 10, 24)

      assert is_list(subnets)
      assert length(subnets) == 256
      assert "100.64.0.0/24" in subnets
      assert "100.64.255.0/24" in subnets
    end
  end

  describe "find_available_subnet/3" do
    test "finds first available subnet not in existing list" do
      existing = ["100.64.0.0/24", "100.64.1.0/24"]

      subnet = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)

      assert subnet == "100.64.2.0/24"
    end

    test "skips used subnets and finds next available" do
      existing = ["100.64.0.0/24", "100.64.1.0/24", "100.64.2.0/24", "100.64.3.0/24"]

      subnet = Vpn.find_available_subnet("100.64.0.0/10", 24, existing)

      assert subnet == "100.64.4.0/24"
    end
  end
end
