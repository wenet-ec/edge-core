# edge_admin/test/edge_admin/nodes/checks/create_cluster_check_test.exs
defmodule EdgeAdmin.Nodes.Checks.CreateClusterCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Checks.CreateClusterCheck

  # ---------------------------------------------------------------------------
  # check/2 — nil (auto-generate path)
  # ---------------------------------------------------------------------------

  describe "check/2 — nil range" do
    test "passes when ipv4_range is nil" do
      assert :ok = CreateClusterCheck.check(nil, ["100.64.0.0/24"])
    end

    test "passes when ipv4_range is nil and existing list is empty" do
      assert :ok = CreateClusterCheck.check(nil, [])
    end
  end

  # ---------------------------------------------------------------------------
  # check/2 — no overlap
  # ---------------------------------------------------------------------------

  describe "check/2 — non-overlapping ranges" do
    test "passes when existing list is empty" do
      assert :ok = CreateClusterCheck.check("100.64.1.0/24", [])
    end

    test "passes when proposed range is in a completely different space" do
      assert :ok = CreateClusterCheck.check("192.168.1.0/24", ["10.0.0.0/24"])
    end

    test "passes for adjacent /24 ranges in the same /16" do
      assert :ok = CreateClusterCheck.check("100.64.2.0/24", ["100.64.1.0/24"])
    end

    test "passes when multiple non-overlapping clusters exist" do
      existing = ["100.64.0.0/24", "100.64.1.0/24"]
      assert :ok = CreateClusterCheck.check("100.64.2.0/24", existing)
    end
  end

  # ---------------------------------------------------------------------------
  # check/2 — overlap detected
  # ---------------------------------------------------------------------------

  describe "check/2 — overlapping ranges" do
    test "returns conflict for exact duplicate range" do
      assert {:error, {:conflict, reason}} =
               CreateClusterCheck.check("100.64.1.0/24", ["100.64.1.0/24"])

      assert reason =~ "overlaps"
    end

    test "returns conflict when proposed /24 is contained within existing /16" do
      assert {:error, {:conflict, reason}} =
               CreateClusterCheck.check("100.64.1.0/24", ["100.64.0.0/16"])

      assert reason =~ "overlaps"
    end

    test "returns conflict when proposed /16 contains an existing /24" do
      assert {:error, {:conflict, reason}} =
               CreateClusterCheck.check("100.64.0.0/16", ["100.64.1.0/24"])

      assert reason =~ "overlaps"
    end

    test "returns conflict when one of many existing ranges overlaps" do
      existing = ["10.0.0.0/24", "10.0.1.0/24", "100.64.0.0/16"]

      assert {:error, {:conflict, _reason}} =
               CreateClusterCheck.check("100.64.5.0/24", existing)
    end

    test "error message includes the proposed range" do
      {:error, {:conflict, reason}} =
        CreateClusterCheck.check("100.64.3.0/24", ["100.64.0.0/16"])

      assert reason =~ "100.64.3.0/24"
    end
  end
end
