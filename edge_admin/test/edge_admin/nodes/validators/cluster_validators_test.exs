# edge_admin/test/edge_admin/nodes/validators/cluster_validators_test.exs
defmodule EdgeAdmin.Nodes.Validators.ClusterValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Validators.ClusterValidators

  test "validates cluster names" do
    assert ClusterValidators.valid_name?("production-1")
    refute ClusterValidators.valid_name?("default")
    refute ClusterValidators.valid_name?("Bad Name")
  end

  test "validates node limits" do
    assert ClusterValidators.valid_node_limit?(nil)
    assert ClusterValidators.valid_node_limit?(1)
    refute ClusterValidators.valid_node_limit?(0)
    refute ClusterValidators.valid_node_limit?(-1)
  end

  test "validates basic CIDR shapes" do
    assert ClusterValidators.valid_ipv4_cidr_format?("100.64.1.0/24")
    refute ClusterValidators.valid_ipv4_cidr_format?("100.64.1.0")
    assert ClusterValidators.valid_ipv6_cidr_format?("fd7a:91c2:4e8b::/64")
    refute ClusterValidators.valid_ipv6_cidr_format?("not-a-cidr")
  end

  test "validates cluster CIDR policies" do
    assert ClusterValidators.ipv4_range_error("100.64.1.0/24") == :ok
    assert {:error, message} = ClusterValidators.ipv4_range_error("10.0.0.0/24")
    assert message =~ "private"
    assert ClusterValidators.ipv6_range_error("fd7a:91c2:4e8b::/64") == :ok
    assert {:error, _message} = ClusterValidators.ipv6_range_error("2001:db8::/64")
  end
end
