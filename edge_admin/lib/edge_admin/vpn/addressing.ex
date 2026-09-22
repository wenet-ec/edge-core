# edge_admin/lib/edge_admin/vpn/addressing.ex
defmodule EdgeAdmin.Vpn.Addressing do
  @moduledoc "Pure IPv4/IPv6 CIDR parsing, overlap, and subnet allocation helpers."

  import Bitwise

  def cluster_auto_generated_v4_ranges, do: Application.get_env(:edge_admin, :cluster_auto_generated_v4_ranges)
  def cluster_v4_subnet_prefix, do: Application.get_env(:edge_admin, :cluster_v4_subnet_prefix)
  def cluster_auto_generated_v6_ranges, do: Application.get_env(:edge_admin, :cluster_auto_generated_v6_ranges)
  def cluster_v6_subnet_prefix, do: Application.get_env(:edge_admin, :cluster_v6_subnet_prefix, 64)

  @spec usable_ipv4_capacity(0..32) :: non_neg_integer()
  def usable_ipv4_capacity(prefix) when prefix in 0..32 do
    Integer.pow(2, 32 - prefix) - 1
  end

  @doc """
  Parses a CIDR string into IP tuple and prefix.
  """
  @spec parse_cidr(String.t()) :: {:ok, {:inet.ip4_address(), 0..32}} | {:error, String.t()}
  def parse_cidr(cidr) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [ip_str, prefix_str] ->
        with {:ok, ip_tuple} <- parse_ipv4(ip_str),
             {prefix, ""} <- Integer.parse(prefix_str),
             true <- prefix >= 0 and prefix <= 32 do
          {:ok, {ip_tuple, prefix}}
        else
          _ -> {:error, "invalid CIDR format"}
        end

      _ ->
        {:error, "invalid CIDR format"}
    end
  end

  @doc "Returns an IPv4 CIDR with its address aligned to the network boundary."
  @spec normalize_ipv4_cidr(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_ipv4_cidr(cidr) do
    with {:ok, {address, prefix}} <- parse_cidr(cidr) do
      normalized_address = address |> ip_to_int() |> band(prefix_to_mask(prefix))
      {:ok, "#{int_to_ip_string(normalized_address)}/#{prefix}"}
    end
  end

  @doc "Normalizes an IPv4 CIDR or raises for invalid input."
  @spec normalize_ipv4_cidr!(String.t()) :: String.t()
  def normalize_ipv4_cidr!(cidr), do: normalize_cidr!(cidr, &normalize_ipv4_cidr/1, :ipv4)

  @doc "Normalizes an IPv4 CIDR list, rejects overlaps, and optionally limits prefix length."
  @spec normalize_ipv4_ranges!([String.t()], keyword()) :: [String.t()]
  def normalize_ipv4_ranges!(ranges, opts \\ []) do
    normalize_ranges!(ranges, &normalize_ipv4_cidr/1, Keyword.get(opts, :max_prefix, 32), :ipv4)
  end

  @doc "Raises when IPv4 CIDR ranges overlap; returns the input otherwise."
  @spec ensure_disjoint_ipv4_ranges!([String.t()]) :: [String.t()]
  def ensure_disjoint_ipv4_ranges!(ranges), do: ensure_disjoint_ranges!(ranges, &ipv4_cidrs_overlap?/2, :ipv4)

  @doc """
  Parses an IPv4 address string into a tuple.
  """
  @spec parse_ipv4(String.t()) :: {:ok, :inet.ip4_address()} | {:error, String.t()}
  def parse_ipv4(ip_str) when is_binary(ip_str) do
    case String.split(ip_str, ".") do
      [a, b, c, d] ->
        with {a_int, ""} <- Integer.parse(a),
             {b_int, ""} <- Integer.parse(b),
             {c_int, ""} <- Integer.parse(c),
             {d_int, ""} <- Integer.parse(d),
             true <- Enum.all?([a_int, b_int, c_int, d_int], &(&1 >= 0 and &1 <= 255)) do
          {:ok, {a_int, b_int, c_int, d_int}}
        else
          _ -> {:error, "invalid IPv4 address"}
        end

      _ ->
        {:error, "invalid IPv4 address"}
    end
  end

  @doc """
  Generates the next available IPv4 range from configured pools.

  Excludes any ranges in the provided list.
  """
  def generate_next_subnet(existing_ranges \\ []) do
    base_ranges = cluster_auto_generated_v4_ranges()
    target_prefix = cluster_v4_subnet_prefix()

    # Try to find available subnet from each base range
    case Enum.find_value(base_ranges, fn base_range ->
           find_available_subnet(base_range, target_prefix, existing_ranges)
         end) do
      nil -> {:error, {:conflict, "address_pool_exhausted: no IPv4 subnets remain in the configured allocation pools"}}
      subnet -> {:ok, subnet}
    end
  end

  @doc "Generates the first non-overlapping IPv6 subnet from the configured ULA pools."
  @spec generate_next_ipv6_subnet([String.t()]) :: {:ok, String.t()} | {:error, {:conflict, String.t()}}
  def generate_next_ipv6_subnet(existing_ranges \\ []) do
    target_prefix = cluster_v6_subnet_prefix()

    case Enum.find_value(cluster_auto_generated_v6_ranges(), fn base_range ->
           find_available_ipv6_subnet(base_range, target_prefix, existing_ranges)
         end) do
      nil -> {:error, {:conflict, "address_pool_exhausted: no IPv6 /64 subnets remain in the configured ULA pools"}}
      subnet -> {:ok, subnet}
    end
  end

  @doc """
  Finds an available subnet within a base CIDR range.
  """
  def find_available_subnet(base_cidr, target_prefix, existing_ranges) do
    case parse_cidr(base_cidr) do
      {:ok, {base_ip, base_prefix}} ->
        subnets = generate_subnets(base_ip, base_prefix, target_prefix)

        Enum.find(subnets, fn subnet ->
          not ipv4_cidrs_overlap?(subnet, existing_ranges)
        end)

      _ ->
        nil
    end
  end

  @doc false
  def find_available_ipv6_subnet(base_cidr, target_prefix, existing_ranges) do
    with {:ok, {base_ip, base_prefix}} <- parse_ipv6_cidr(base_cidr),
         true <- target_prefix >= base_prefix and target_prefix <= 128 do
      base_int = ipv6_to_int(base_ip) &&& ipv6_prefix_to_mask(base_prefix)
      count = 1 <<< (target_prefix - base_prefix)
      step = 1 <<< (128 - target_prefix)

      0..(count - 1)
      |> Stream.map(fn index ->
        "#{ipv6_int_to_string(base_int + index * step)}/#{target_prefix}"
      end)
      |> Enum.find(fn subnet -> not ipv6_cidrs_overlap?(subnet, existing_ranges) end)
    else
      _ -> nil
    end
  end

  @doc "Parses an IPv6 CIDR into its 8-tuple address and prefix length."
  @spec parse_ipv6_cidr(String.t()) ::
          {:ok, {{0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535}, 0..128}}
          | {:error, String.t()}
  def parse_ipv6_cidr(cidr) when is_binary(cidr) do
    with [address, prefix_string] <- String.split(cidr, "/", parts: 2),
         {prefix, ""} <- Integer.parse(prefix_string),
         true <- prefix >= 0 and prefix <= 128,
         {:ok, address_tuple} <- :inet.parse_address(String.to_charlist(address)),
         true <- tuple_size(address_tuple) == 8 do
      {:ok, {address_tuple, prefix}}
    else
      _ -> {:error, "invalid IPv6 CIDR format"}
    end
  end

  def parse_ipv6_cidr(_), do: {:error, "invalid IPv6 CIDR format"}

  @doc "Returns an IPv6 CIDR with its address aligned to the network boundary."
  @spec normalize_ipv6_cidr(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_ipv6_cidr(cidr) do
    with {:ok, {address, prefix}} <- parse_ipv6_cidr(cidr) do
      normalized_address = address |> ipv6_to_int() |> band(ipv6_prefix_to_mask(prefix))
      {:ok, "#{ipv6_int_to_string(normalized_address)}/#{prefix}"}
    end
  end

  @doc "Normalizes an IPv6 CIDR or raises for invalid input."
  @spec normalize_ipv6_cidr!(String.t()) :: String.t()
  def normalize_ipv6_cidr!(cidr), do: normalize_cidr!(cidr, &normalize_ipv6_cidr/1, :ipv6)

  @doc "Normalizes an IPv6 CIDR list, rejects overlaps, and optionally limits prefix length."
  @spec normalize_ipv6_ranges!([String.t()], keyword()) :: [String.t()]
  def normalize_ipv6_ranges!(ranges, opts \\ []) do
    normalize_ranges!(ranges, &normalize_ipv6_cidr/1, Keyword.get(opts, :max_prefix, 128), :ipv6)
  end

  @doc "Raises when IPv6 CIDR ranges overlap; returns the input otherwise."
  @spec ensure_disjoint_ipv6_ranges!([String.t()]) :: [String.t()]
  def ensure_disjoint_ipv6_ranges!(ranges), do: ensure_disjoint_ranges!(ranges, &ipv6_cidrs_overlap?/2, :ipv6)

  @doc "Returns whether an IPv6 CIDR intersects any IPv6 CIDR in the given list."
  @spec ipv6_cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  def ipv6_cidrs_overlap?(cidr, existing_ranges) do
    case parse_ipv6_cidr(cidr) do
      {:ok, {ip, prefix}} ->
        Enum.any?(existing_ranges, fn existing ->
          case parse_ipv6_cidr(existing) do
            {:ok, {existing_ip, existing_prefix}} ->
              ipv6_contains?(ip, prefix, existing_ip) or ipv6_contains?(existing_ip, existing_prefix, ip)

            _ ->
              false
          end
        end)

      _ ->
        false
    end
  end

  defp ipv6_contains?(network, prefix, address) do
    mask = ipv6_prefix_to_mask(prefix)
    (ipv6_to_int(network) &&& mask) == (ipv6_to_int(address) &&& mask)
  end

  defp normalize_ranges!([], _normalize, _max_prefix, family) do
    raise ArgumentError, "#{family} CIDR range list must contain at least one CIDR"
  end

  defp normalize_ranges!(ranges, normalize, max_prefix, family) do
    ranges
    |> Enum.map(fn range ->
      with {:ok, normalized} <- normalize.(range),
           {:ok, {_address, prefix}} <- parse_range(normalized, family),
           true <- prefix <= max_prefix do
        normalized
      else
        _ -> raise ArgumentError, "invalid #{family} CIDR range #{inspect(range)}"
      end
    end)
    |> ensure_disjoint_ranges!(family_overlap_function(family), family)
  end

  defp normalize_cidr!(cidr, normalize, family) do
    case normalize.(cidr) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> raise ArgumentError, "invalid #{family} CIDR #{inspect(cidr)}"
    end
  end

  defp parse_range(range, :ipv4), do: parse_cidr(range)
  defp parse_range(range, :ipv6), do: parse_ipv6_cidr(range)

  defp ensure_disjoint_ranges!(ranges, overlap?, family) do
    ranges
    |> Enum.with_index()
    |> Enum.each(fn {range, index} ->
      previous_ranges = Enum.take(ranges, index)

      if Enum.any?(previous_ranges, fn previous -> overlap?.(range, [previous]) end) do
        raise ArgumentError, "overlapping #{family} CIDR ranges include #{inspect(range)}"
      end
    end)

    ranges
  end

  defp family_overlap_function(:ipv4), do: &ipv4_cidrs_overlap?/2
  defp family_overlap_function(:ipv6), do: &ipv6_cidrs_overlap?/2

  defp ipv6_prefix_to_mask(0), do: 0
  defp ipv6_prefix_to_mask(prefix), do: ((1 <<< 128) - 1) <<< (128 - prefix) &&& (1 <<< 128) - 1

  defp ipv6_to_int(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(0, fn segment, acc -> (acc <<< 16) + segment end)
  end

  defp ipv6_int_to_string(integer) do
    tuple =
      0..7
      |> Enum.reverse()
      |> Enum.map(fn shift -> integer >>> (shift * 16) &&& 0xFFFF end)
      |> List.to_tuple()

    tuple |> :inet.ntoa() |> List.to_string()
  end

  @doc """
  Returns true if the given CIDR string overlaps with any range in the list.
  Overlap means one network contains the other's network address (either direction).
  """
  @spec ipv4_cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  def ipv4_cidrs_overlap?(cidr, existing_ranges) do
    case parse_cidr(cidr) do
      {:ok, {ip, prefix}} ->
        Enum.any?(existing_ranges, fn existing ->
          case parse_cidr(existing) do
            {:ok, {ex_ip, ex_prefix}} -> cidr_intersect?({ip, prefix}, {ex_ip, ex_prefix})
            _ -> false
          end
        end)

      _ ->
        false
    end
  end

  # Two CIDRs intersect if one network address falls inside the other's range.
  defp cidr_intersect?({ip1, prefix1}, {ip2, prefix2}) do
    ip_contains?(ip1, prefix1, ip2) or ip_contains?(ip2, prefix2, ip1)
  end

  # Returns true if ip_addr falls within the network defined by net_ip/prefix.
  defp ip_contains?({a, b, c, d}, prefix, {ta, tb, tc, td}) do
    mask = prefix_to_mask(prefix)
    band(ip_to_int({a, b, c, d}), mask) == band(ip_to_int({ta, tb, tc, td}), mask)
  end

  defp ip_to_int({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d

  defp prefix_to_mask(0), do: 0
  defp prefix_to_mask(prefix), do: 0xFFFFFFFF |> bsl(32 - prefix) |> band(0xFFFFFFFF)

  @doc """
  Generates candidate subnets within a base range as a lazy stream.

  Works for any `base_prefix <= target_prefix` pair. The base IP is realigned
  to its prefix boundary before subnet generation.

  Returns a `Stream` so large allocation pools can be consumed lazily.

  Raises `ArgumentError` on misconfiguration (operator-fixable, not user input):
    * `target_prefix < base_prefix` — can't carve a wider subnet from a narrower pool
    * `base_prefix` outside `0..32` or `target_prefix` outside `0..32`
  """
  @spec generate_subnets(:inet.ip4_address(), 0..32, 0..32) :: Enumerable.t(String.t())
  def generate_subnets({_, _, _, _} = base_ip, base_prefix, target_prefix)
      when is_integer(base_prefix) and is_integer(target_prefix) do
    cond do
      base_prefix < 0 or base_prefix > 32 ->
        raise ArgumentError, "base_prefix must be in 0..32, got #{base_prefix}"

      target_prefix < 0 or target_prefix > 32 ->
        raise ArgumentError, "target_prefix must be in 0..32, got #{target_prefix}"

      target_prefix < base_prefix ->
        raise ArgumentError,
              "target_prefix (#{target_prefix}) must be >= base_prefix (#{base_prefix}); " <>
                "cannot carve a wider subnet than the pool"

      true ->
        aligned_base_int = base_ip |> ip_to_int() |> band(prefix_to_mask(base_prefix))
        count = 1 <<< (target_prefix - base_prefix)
        step = 1 <<< (32 - target_prefix)

        Stream.map(0..(count - 1), fn i ->
          subnet_int = aligned_base_int + i * step
          "#{int_to_ip_string(subnet_int)}/#{target_prefix}"
        end)
    end
  end

  defp int_to_ip_string(int) do
    a = int |> bsr(24) |> band(0xFF)
    b = int |> bsr(16) |> band(0xFF)
    c = int |> bsr(8) |> band(0xFF)
    d = band(int, 0xFF)
    "#{a}.#{b}.#{c}.#{d}"
  end
end
