# edge_admin/lib/edge_admin/nodes/checks/subnet_overlap_check.ex
defmodule EdgeAdmin.Nodes.Checks.SubnetOverlapCheck do
  @moduledoc """
  Checks that a proposed IPv4 range does not overlap with any existing cluster range.

  Overlap means one network's address falls inside the other's range (either direction),
  which would cause Netmaker to reject the network with "network cidr already in use".

  Accepts the existing ranges as a parameter so the caller can reuse the same query
  result for auto-generating a subnet when no range is supplied.
  """

  alias EdgeAdmin.Vpn

  @spec check(String.t() | nil, [String.t()]) :: :ok | {:error, {:conflict, String.t()}}
  def check(nil, _existing_ranges), do: :ok

  def check(ipv4_range, existing_ranges) do
    if Vpn.cidrs_overlap?(ipv4_range, existing_ranges) do
      {:error, {:conflict, "#{ipv4_range} overlaps with an existing cluster range"}}
    else
      :ok
    end
  end
end
