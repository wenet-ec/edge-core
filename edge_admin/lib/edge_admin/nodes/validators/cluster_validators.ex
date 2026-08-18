# edge_admin/lib/edge_admin/nodes/validators/cluster_validators.ex
defmodule EdgeAdmin.Nodes.Validators.ClusterValidators do
  @moduledoc """
  Pure value-level validators for cluster data.

  These functions centralize invariant cluster-value rules while leaving
  changeset composition and cross-record checks to their owning layers.
  """

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Vpn

  @min_ipv4_prefix 30

  @doc "Returns whether a cluster name satisfies its invariant format rules."
  @spec valid_name?(term()) :: boolean()
  def valid_name?(name), do: name_error(name) == :ok

  @doc "Returns the invariant cluster-name error, if any."
  @spec name_error(term()) :: :ok | {:error, String.t()}
  def name_error(name) when is_binary(name) do
    cond do
      byte_size(name) > Naming.cluster_name_max_length() ->
        {:error, "should be at most #{Naming.cluster_name_max_length()} character(s)"}

      name == "default" ->
        {:error, "is reserved"}

      not Regex.match?(Naming.cluster_name_regex(), name) ->
        {:error, "must be lowercase alphanumeric with hyphens, cannot start/end with hyphen"}

      true ->
        :ok
    end
  end

  def name_error(_name), do: {:error, "has invalid format"}

  @doc "Returns whether a node limit is nil or a positive integer."
  @spec valid_node_limit?(term()) :: boolean()
  def valid_node_limit?(nil), do: true
  def valid_node_limit?(limit) when is_integer(limit), do: limit > 0
  def valid_node_limit?(_limit), do: false

  @doc "Returns whether a value has the basic IPv4 CIDR input shape."
  @spec valid_ipv4_cidr_format?(term()) :: boolean()
  def valid_ipv4_cidr_format?(value) when is_binary(value) do
    Regex.match?(~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/, value)
  end

  def valid_ipv4_cidr_format?(_value), do: false

  @doc "Returns whether a value has the basic IPv6 CIDR input shape."
  @spec valid_ipv6_cidr_format?(term()) :: boolean()
  def valid_ipv6_cidr_format?(value) when is_binary(value) do
    Regex.match?(~r/^[0-9A-Fa-f:]+\/[0-9]{1,3}$/, value)
  end

  def valid_ipv6_cidr_format?(_value), do: false

  @doc "Validates an IPv4 cluster range and returns a user-facing reason on failure."
  @spec ipv4_range_error(term()) :: :ok | {:error, String.t()}
  def ipv4_range_error(range) do
    case Vpn.parse_cidr(range) do
      {:ok, {ip_tuple, prefix}} when prefix <= @min_ipv4_prefix ->
        if excluded_range?(ip_tuple) do
          {:error, "cannot use private, loopback, link-local, or multicast ranges"}
        else
          :ok
        end

      {:ok, {_ip_tuple, prefix}} ->
        {:error,
         "prefix /#{prefix} is too small — minimum is /#{@min_ipv4_prefix} (#{Vpn.usable_ipv4_capacity(@min_ipv4_prefix)} usable IPs)"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Validates that a cluster range is a private ULA /64 IPv6 CIDR."
  @spec ipv6_range_error(term()) :: :ok | {:error, String.t()}
  def ipv6_range_error(range) do
    case Vpn.parse_ipv6_cidr(range) do
      {:ok, {ip, 64}} ->
        if ula_ipv6?(ip), do: :ok, else: {:error, "must be a private ULA range under fd00::/8"}

      {:ok, {_ip, prefix}} ->
        {:error, "must use a /64 prefix (got /#{prefix})"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns whether a node limit fits the usable capacity of an IPv4 range."
  @spec node_limit_fits_ipv4_range?(term(), term(), non_neg_integer()) :: boolean()
  def node_limit_fits_ipv4_range?(nil, _range, _reservation), do: true

  def node_limit_fits_ipv4_range?(limit, range, reservation)
      when is_integer(limit) and is_integer(reservation) and reservation >= 0 do
    case Vpn.parse_cidr(range) do
      {:ok, {_ip, prefix}} ->
        limit <= Vpn.usable_ipv4_capacity(prefix) - reservation

      {:error, _reason} ->
        true
    end
  end

  def node_limit_fits_ipv4_range?(_limit, _range, _reservation), do: true

  defp ula_ipv6?({first, _, _, _, _, _, _, _}), do: first >= 0xFD00 and first <= 0xFDFF

  defp excluded_range?({a, _, _, _}) do
    a in [0, 10, 127, 169, 172, 192, 224, 240, 255]
  end
end
