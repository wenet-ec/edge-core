# edge_agent/lib/edge_agent/ingress_tunneling/configuration.ex
defmodule EdgeAgent.IngressTunneling.Configuration do
  @moduledoc "Validates complete Ingress Tunneling snapshots before they reach the runtime."

  @spec validate(map()) :: {:ok, map()} | {:error, atom()}
  def validate(
        %{
          "ingress_public_key" => ingress_key,
          "ingress_ipv4_addresses" => ingress_ipv4,
          "ingress_ipv6_addresses" => ingress_ipv6,
          "vpn_dns_suffix" => dns_suffix,
          "vpn_ipv4_range" => vpn_ipv4,
          "vpn_ipv6_range" => vpn_ipv6,
          "core_derp_map_urls" => derp_urls,
          "core_stun_servers" => stun_servers,
          "peers" => peers
        } = config
      )
      when is_binary(ingress_key) and is_list(ingress_ipv4) and is_list(ingress_ipv6) and is_binary(dns_suffix) and
             is_binary(vpn_ipv4) and is_binary(vpn_ipv6) and is_list(derp_urls) and is_list(stun_servers) and
             is_list(peers) do
    with true <- valid_ingress_identity?(ingress_key),
         true <- valid_ingress_addresses?(ingress_ipv4, ingress_ipv6),
         true <- valid_network_config?(vpn_ipv4, vpn_ipv6, dns_suffix),
         true <- valid_transport_config?(derp_urls, stun_servers),
         true <- valid_peers?(peers, ingress_key),
         :ok <- ingress_addresses_match_peers(ingress_ipv4, ingress_ipv6, peers) do
      {:ok, config}
    else
      _ -> {:error, :invalid_ingress_tunneling_configuration}
    end
  end

  def validate(_config), do: {:error, :invalid_ingress_tunneling_configuration}

  defp valid_ingress_identity?(key), do: key?(key)

  defp valid_ingress_addresses?(ipv4, ipv6) do
    Enum.all?(ipv4, &host_prefix?(&1, 32)) and Enum.all?(ipv6, &host_prefix?(&1, 128)) and
      unique_addresses?(ipv4) and unique_addresses?(ipv6)
  end

  defp valid_network_config?(ipv4, ipv6, dns_suffix) do
    cidr?(ipv4, :inet) and cidr?(ipv6, :inet6) and valid_dns_suffix?(dns_suffix)
  end

  defp valid_transport_config?(derp_urls, stun_servers) do
    Enum.all?(derp_urls, &is_binary/1) and Enum.all?(stun_servers, &is_binary/1)
  end

  defp valid_peers?(peers, ingress_key) do
    Enum.all?(peers, &valid_peer?/1) and Enum.all?(peers, &(&1["tunnel_public_key"] != ingress_key)) and
      unique_peer_fields?(peers)
  end

  defp valid_peer?(%{
         "tunnel_public_key" => key,
         "tunnel_ipv4_address" => ipv4,
         "tunnel_ipv6_address" => ipv6,
         "allowed_ips" => allowed_ips
       })
       when is_binary(key) and is_binary(ipv4) and is_binary(ipv6) and is_list(allowed_ips) do
    key?(key) and host_prefix?(ipv4, 32) and host_prefix?(ipv6, 128) and
      Enum.sort(allowed_ips) == Enum.sort([ipv4, ipv6]) and Enum.all?(allowed_ips, &is_binary/1)
  end

  defp valid_peer?(_peer), do: false

  defp key?(encoded) do
    case Base.decode64(encoded) do
      {:ok, <<_key::binary-size(32)>> = key} ->
        Base.encode64(key) == encoded and key != :binary.copy(<<0>>, 32)

      _ ->
        false
    end
  end

  defp host_prefix?(cidr, expected_prefix) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [address, prefix] ->
        with {prefix, ""} <- Integer.parse(prefix),
             {:ok, parsed} <- :inet.parse_address(String.to_charlist(address)),
             true <- prefix == expected_prefix do
          address_family?(parsed, expected_prefix)
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp host_prefix?(_cidr, _expected_prefix), do: false

  defp cidr?(cidr, family) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [address, prefix] ->
        with {prefix, ""} <- Integer.parse(prefix),
             {:ok, parsed} <- :inet.parse_address(String.to_charlist(address)),
             true <- address_family?(parsed, family),
             true <- prefix in 0..address_bits(parsed) do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp address_family?({_, _, _, _}, :inet), do: true
  defp address_family?({_, _, _, _, _, _, _, _}, :inet6), do: true
  defp address_family?({_, _, _, _}, 32), do: true
  defp address_family?({_, _, _, _, _, _, _, _}, 128), do: true
  defp address_family?(_address, _family), do: false

  defp address_bits({_, _, _, _}), do: 32
  defp address_bits({_, _, _, _, _, _, _, _}), do: 128

  defp valid_dns_suffix?(suffix) do
    suffix != "" and String.length(suffix) <= 253 and
      Enum.all?(String.split(suffix, "."), fn label ->
        label != "" and byte_size(label) <= 63 and
          Regex.match?(~r/^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$/, label)
      end)
  end

  defp unique_peer_fields?(peers) do
    keys = Enum.map(peers, &Map.fetch!(&1, "tunnel_public_key"))
    ipv4 = Enum.map(peers, &Map.fetch!(&1, "tunnel_ipv4_address"))
    ipv6 = Enum.map(peers, &Map.fetch!(&1, "tunnel_ipv6_address"))

    length(keys) == length(Enum.uniq(keys)) and length(ipv4) == length(Enum.uniq(ipv4)) and
      length(ipv6) == length(Enum.uniq(ipv6))
  end

  defp unique_addresses?(addresses), do: length(addresses) == length(Enum.uniq(addresses))

  defp ingress_addresses_match_peers(ipv4, ipv6, peers) do
    cond do
      peers == [] -> :ok
      ipv4 == [] or ipv6 == [] -> {:error, :missing_ingress_addresses}
      Enum.any?(peers, &(&1["tunnel_ipv4_address"] in ipv4)) -> {:error, :duplicate_ingress_address}
      Enum.any?(peers, &(&1["tunnel_ipv6_address"] in ipv6)) -> {:error, :duplicate_ingress_address}
      true -> :ok
    end
  end
end
