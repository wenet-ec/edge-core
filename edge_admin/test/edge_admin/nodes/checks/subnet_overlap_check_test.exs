# edge_admin/test/edge_admin/nodes/checks/subnet_overlap_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.SubnetOverlapCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Checks.SubnetOverlapCheck
  # check/3 — nil (auto-generate path)

  describe "check/3 — nil range" do
    test "passes when ipv4_range is nil" do
      assert :ok = SubnetOverlapCheck.check(nil, ["100.64.0.0/24"], :ipv4)
    end

    test "passes when ipv4_range is nil and existing list is empty" do
      assert :ok = SubnetOverlapCheck.check(nil, [], :ipv4)
    end
  end

  # check/3 — no overlap

  describe "check/3 — non-overlapping ranges" do
    test "passes when existing list is empty" do
      assert :ok = SubnetOverlapCheck.check("100.64.1.0/24", [], :ipv4)
    end

    test "passes when proposed range is in a completely different space" do
      assert :ok = SubnetOverlapCheck.check("192.168.1.0/24", ["10.0.0.0/24"], :ipv4)
    end

    test "passes for adjacent /24 ranges in the same /16" do
      assert :ok = SubnetOverlapCheck.check("100.64.2.0/24", ["100.64.1.0/24"], :ipv4)
    end

    test "passes when multiple non-overlapping clusters exist" do
      existing = ["100.64.0.0/24", "100.64.1.0/24"]
      assert :ok = SubnetOverlapCheck.check("100.64.2.0/24", existing, :ipv4)
    end
  end

  # check/3 — overlap detected

  describe "check/3 — overlapping ranges" do
    test "returns conflict for exact duplicate range" do
      assert {:error, {:conflict, reason}} =
               SubnetOverlapCheck.check("100.64.1.0/24", ["100.64.1.0/24"], :ipv4)

      assert reason =~ "overlaps"
    end

    test "returns conflict when proposed /24 is contained within existing /16" do
      assert {:error, {:conflict, reason}} =
               SubnetOverlapCheck.check("100.64.1.0/24", ["100.64.0.0/16"], :ipv4)

      assert reason =~ "overlaps"
    end

    test "returns conflict when proposed /16 contains an existing /24" do
      assert {:error, {:conflict, reason}} =
               SubnetOverlapCheck.check("100.64.0.0/16", ["100.64.1.0/24"], :ipv4)

      assert reason =~ "overlaps"
    end

    test "returns conflict when one of many existing ranges overlaps" do
      existing = ["10.0.0.0/24", "10.0.1.0/24", "100.64.0.0/16"]

      assert {:error, {:conflict, _reason}} =
               SubnetOverlapCheck.check("100.64.5.0/24", existing, :ipv4)
    end

    test "error message includes the proposed range" do
      {:error, {:conflict, reason}} =
        SubnetOverlapCheck.check("100.64.3.0/24", ["100.64.0.0/16"], :ipv4)

      assert reason =~ "100.64.3.0/24"
    end
  end

  describe "check/3 — address families" do
    test "dispatches IPv6 checks explicitly" do
      assert :ok =
               SubnetOverlapCheck.check("fd7a:91c2:4e8c::/64", ["fd7a:91c2:4e8b::/64"], :ipv6)

      assert {:error, {:conflict, reason}} =
               SubnetOverlapCheck.check(
                 "fd7a:91c2:4e8b::/64",
                 ["fd7a:91c2:4e8b::/48"],
                 :ipv6
               )

      assert reason =~ "IPv6"
    end
  end

  describe "family-specific functions" do
    test "check_ipv4/2 delegates IPv4 validation" do
      assert {:error, {:conflict, _reason}} =
               SubnetOverlapCheck.check_ipv4("100.64.1.0/24", ["100.64.0.0/16"])
    end

    test "check_ipv6/2 delegates IPv6 validation" do
      assert {:error, {:conflict, _reason}} =
               SubnetOverlapCheck.check_ipv6("fd7a:91c2:4e8b::/64", ["fd7a:91c2:4e8b::/48"])
    end
  end
end
