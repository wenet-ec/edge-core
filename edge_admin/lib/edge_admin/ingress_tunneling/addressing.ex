# edge_admin/lib/edge_admin/ingress_tunneling/addressing.ex
defmodule EdgeAdmin.IngressTunneling.Addressing do
  @moduledoc """
  Allocates isolated per-Ingress Tunnel Client transport addresses.

  The configured pools are not connected interface subnets. Each Ingress owns
  the first usable address in its selected pool, and every Tunnel Client gets
  one distinct `/32` and `/128` after it. Different Ingress Nodes intentionally
  reuse the same allocations.
  """

  import Bitwise

  alias EdgeAdmin.Vpn

  @type allocation :: %{
          ingress_ipv4_address: String.t(),
          ingress_ipv6_address: String.t(),
          tunnel_ipv4_address: String.t(),
          tunnel_ipv6_address: String.t()
        }
  @type allocation_error :: {:error, {:conflict, String.t()}}

  @doc "Allocates the next free IPv4 and IPv6 addresses from the configured pools."
  @spec allocate([String.t()], [String.t()]) :: {:ok, allocation()} | allocation_error()
  def allocate(existing_ipv4_addresses, existing_ipv6_addresses) do
    allocate(
      existing_ipv4_addresses,
      existing_ipv6_addresses,
      ingress_tunnel_auto_generated_v4_ranges(),
      ingress_tunnel_auto_generated_v6_ranges()
    )
  end

  @doc false
  @spec allocate([String.t()], [String.t()], [String.t()], [String.t()]) ::
          {:ok, allocation()} | allocation_error()
  def allocate(existing_ipv4_addresses, existing_ipv6_addresses, ipv4_ranges, ipv6_ranges) do
    with {:ok, ipv4_allocation} <- next_ipv4_allocation(existing_ipv4_addresses, ipv4_ranges),
         {:ok, ipv6_allocation} <- next_ipv6_allocation(existing_ipv6_addresses, ipv6_ranges) do
      {:ok, Map.merge(ipv4_allocation, ipv6_allocation)}
    end
  end

  @doc false
  @spec next_ipv4_address([String.t()], [String.t()]) :: {:ok, String.t()} | allocation_error()
  def next_ipv4_address(existing_addresses, ranges \\ ingress_tunnel_auto_generated_v4_ranges()) do
    with {:ok, %{tunnel_ipv4_address: tunnel_ipv4_address}} <- next_ipv4_allocation(existing_addresses, ranges) do
      {:ok, tunnel_ipv4_address}
    end
  end

  @doc false
  @spec next_ipv6_address([String.t()], [String.t()]) :: {:ok, String.t()} | allocation_error()
  def next_ipv6_address(existing_addresses, ranges \\ ingress_tunnel_auto_generated_v6_ranges()) do
    with {:ok, %{tunnel_ipv6_address: tunnel_ipv6_address}} <- next_ipv6_allocation(existing_addresses, ranges) do
      {:ok, tunnel_ipv6_address}
    end
  end

  defp next_ipv4_allocation(existing_addresses, ranges) do
    used_addresses = existing_addresses |> Enum.flat_map(&parse_ipv4_address/1) |> MapSet.new()

    case Enum.find_value(ranges, &next_ipv4_allocation_in_range(&1, used_addresses)) do
      nil ->
        {:error,
         {:conflict, "tunnel_address_pool_exhausted: no IPv4 addresses remain in the configured allocation pools"}}

      allocation ->
        {:ok, allocation}
    end
  end

  defp next_ipv6_allocation(existing_addresses, ranges) do
    used_addresses = existing_addresses |> Enum.flat_map(&parse_ipv6_address/1) |> MapSet.new()

    case Enum.find_value(ranges, &next_ipv6_allocation_in_range(&1, used_addresses)) do
      nil ->
        {:error,
         {:conflict, "tunnel_address_pool_exhausted: no IPv6 addresses remain in the configured allocation pools"}}

      allocation ->
        {:ok, allocation}
    end
  end

  defp ingress_tunnel_auto_generated_v4_ranges do
    Application.fetch_env!(:edge_admin, :ingress_tunnel_auto_generated_v4_ranges)
  end

  defp ingress_tunnel_auto_generated_v6_ranges do
    Application.fetch_env!(:edge_admin, :ingress_tunnel_auto_generated_v6_ranges)
  end

  defp next_ipv4_allocation_in_range(range, used_addresses) do
    case Vpn.parse_cidr(range) do
      {:ok, {address, prefix}} ->
        first_address = ipv4_to_int(address) &&& ipv4_mask(prefix)
        last_address = first_address + (1 <<< (32 - prefix)) - 1

        ingress_address = first_address + 1
        first_client_address = ingress_address + 1

        if first_client_address <= last_address do
          first_client_address..last_address
          |> Stream.reject(&MapSet.member?(used_addresses, &1))
          |> Enum.take(1)
          |> case do
            [address_integer] ->
              %{
                ingress_ipv4_address: ipv4_address_string(ingress_address),
                tunnel_ipv4_address: ipv4_address_string(address_integer)
              }

            [] ->
              nil
          end
        end

      _ ->
        nil
    end
  end

  defp next_ipv6_allocation_in_range(range, used_addresses) do
    case Vpn.parse_ipv6_cidr(range) do
      {:ok, {address, prefix}} ->
        first_address = ipv6_to_int(address) &&& ipv6_mask(prefix)
        last_address = first_address + (1 <<< (128 - prefix)) - 1

        ingress_address = first_address + 1
        first_client_address = ingress_address + 1

        if first_client_address <= last_address do
          first_client_address..last_address
          |> Stream.reject(&MapSet.member?(used_addresses, &1))
          |> Enum.take(1)
          |> case do
            [address_integer] ->
              %{
                ingress_ipv6_address: ipv6_address_string(ingress_address),
                tunnel_ipv6_address: ipv6_address_string(address_integer)
              }

            [] ->
              nil
          end
        end

      _ ->
        nil
    end
  end

  defp parse_ipv4_address(address) do
    case Vpn.parse_cidr(address) do
      {:ok, {ip, 32}} -> [ipv4_to_int(ip)]
      _ -> []
    end
  end

  defp parse_ipv6_address(address) do
    case Vpn.parse_ipv6_cidr(address) do
      {:ok, {ip, 128}} -> [ipv6_to_int(ip)]
      _ -> []
    end
  end

  defp ipv4_address_string(address),
    do: address |> int_to_ipv4() |> :inet.ntoa() |> List.to_string() |> then(&"#{&1}/32")

  defp ipv6_address_string(address),
    do: address |> int_to_ipv6() |> :inet.ntoa() |> List.to_string() |> then(&"#{&1}/128")

  defp ipv4_to_int({a, b, c, d}), do: (a <<< 24) + (b <<< 16) + (c <<< 8) + d

  defp int_to_ipv4(address),
    do: {address >>> 24 &&& 0xFF, address >>> 16 &&& 0xFF, address >>> 8 &&& 0xFF, address &&& 0xFF}

  defp ipv4_mask(0), do: 0
  defp ipv4_mask(prefix), do: ((1 <<< 32) - 1) <<< (32 - prefix) &&& (1 <<< 32) - 1

  defp ipv6_to_int(address),
    do: address |> Tuple.to_list() |> Enum.reduce(0, fn segment, acc -> (acc <<< 16) + segment end)

  defp int_to_ipv6(address) do
    0..7
    |> Enum.reverse()
    |> Enum.map(&(address >>> (&1 * 16) &&& 0xFFFF))
    |> List.to_tuple()
  end

  defp ipv6_mask(0), do: 0
  defp ipv6_mask(prefix), do: ((1 <<< 128) - 1) <<< (128 - prefix) &&& (1 <<< 128) - 1
end
