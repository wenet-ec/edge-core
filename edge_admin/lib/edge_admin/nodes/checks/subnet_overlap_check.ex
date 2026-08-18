# edge_admin/lib/edge_admin/nodes/checks/subnet_overlap_check.ex
defmodule EdgeAdmin.Nodes.Checks.SubnetOverlapCheck do
  @moduledoc """
  Checks that a proposed address-family range does not overlap with existing ranges.

  Overlap means one network's address falls inside the other's range (either direction),
  which would cause Edge VPN to reject the network with "network cidr already in use".

  Accepts the existing ranges as a parameter so the caller can reuse the same query
  result for auto-generating a subnet when no range is supplied.
  """

  alias EdgeAdmin.Vpn

  @type address_family :: :ipv4 | :ipv6

  @doc "Checks whether a range overlaps an existing range for the requested address family."
  @spec check(String.t() | nil, [String.t()], address_family()) ::
          :ok | {:error, {:conflict, String.t()}}
  def check(range, existing_ranges, :ipv4), do: check_ipv4(range, existing_ranges)
  def check(range, existing_ranges, :ipv6), do: check_ipv6(range, existing_ranges)

  @doc "Checks whether an IPv4 range overlaps an existing cluster range."
  @spec check_ipv4(String.t() | nil, [String.t()]) :: :ok | {:error, {:conflict, String.t()}}
  def check_ipv4(nil, _existing_ranges), do: :ok

  def check_ipv4(ipv4_range, existing_ranges) do
    if Vpn.ipv4_cidrs_overlap?(ipv4_range, existing_ranges) do
      {:error, {:conflict, "#{ipv4_range} overlaps with an existing cluster range"}}
    else
      :ok
    end
  end

  @doc "Checks whether an IPv6 range overlaps an existing cluster range."
  @spec check_ipv6(String.t() | nil, [String.t()]) :: :ok | {:error, {:conflict, String.t()}}
  def check_ipv6(nil, _existing_ranges), do: :ok

  def check_ipv6(ipv6_range, existing_ranges) do
    if Vpn.ipv6_cidrs_overlap?(ipv6_range, existing_ranges) do
      {:error, {:conflict, "#{ipv6_range} overlaps with an existing IPv6 network range"}}
    else
      :ok
    end
  end
end
