# edge_agent/lib/edge_agent/ingress_tunneling/derp/derp_map.ex
defmodule EdgeAgent.IngressTunneling.Derp.DerpMap do
  @moduledoc "Selects deterministic DERP regions and relay nodes from the shared map."

  import Bitwise

  @mask 0xFFFFFFFF
  @fnv_offset 2_166_136_261
  @fnv_prime 16_777_619

  @spec select_relays(map(), binary(), binary()) :: [map()]
  def select_relays(%{"Regions" => regions}, local_key, peer_key)
      when is_map(regions) and is_binary(local_key) and is_binary(peer_key) and byte_size(local_key) == 32 and
             byte_size(peer_key) == 32 do
    pair_seed = pair_seed(local_key, peer_key)

    regions
    |> Enum.flat_map(&parse_region/1)
    |> Enum.map(fn region -> {score(pair_seed, <<region.id::unsigned-big-32>>), region} end)
    |> case do
      [] ->
        []

      scored_regions ->
        {_score, region} = Enum.max_by(scored_regions, fn {score, region} -> {score, -region.id} end)
        rank_nodes(region, pair_seed)
    end
  end

  def select_relays(_derp_map, _local_key, _peer_key), do: []

  defp parse_region({raw_id, %{"Nodes" => nodes}}) when is_binary(raw_id) and is_list(nodes) do
    with {id, ""} when id in 1..0xFFFFFFFF <- Integer.parse(raw_id),
         parsed_nodes when parsed_nodes != [] <- Enum.flat_map(nodes, &parse_node/1) do
      [%{id: id, nodes: parsed_nodes}]
    else
      _ -> []
    end
  end

  defp parse_region(_region), do: []

  defp parse_node(%{"HostName" => host} = node) when is_binary(host) and host != "" do
    port =
      case Map.get(node, "DERPPort") do
        nil -> 443
        0 -> 443
        port -> port
      end

    tls_server_name = Map.get(node, "CertName")
    name = Map.get(node, "Name")

    if is_integer(port) and port in 1..65_535 and (is_nil(tls_server_name) or is_binary(tls_server_name)) do
      [
        %{
          host: host,
          port: port,
          tls_server_name: tls_server_name,
          node_id: if(is_binary(name) and name != "", do: name, else: node_identity(node, host, port))
        }
      ]
    else
      []
    end
  end

  defp parse_node(_node), do: []

  defp rank_nodes(region, pair_seed) do
    region.nodes
    |> Enum.map(fn node -> {score(pair_seed, node.node_id), Map.put(node, :region_id, region.id)} end)
    |> Enum.sort_by(fn {score, node} -> {-score, node.node_id} end)
    |> Enum.map(&elem(&1, 1))
  end

  defp node_identity(%{"IPv4" => ipv4, "IPv6" => ipv6}, host, port), do: "#{host}|#{ipv4}|#{ipv6}|#{port}"

  defp node_identity(_node, host, port), do: "#{host}|||#{port}"

  defp pair_seed(local_key, peer_key) do
    [first, second] = Enum.sort([local_key, peer_key])
    hash(first <> second)
  end

  defp score(seed, value), do: hash(<<seed::unsigned-big-32>> <> value)

  defp hash(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.reduce(@fnv_offset, fn byte, hash ->
      band(bxor(hash, byte) * @fnv_prime, @mask)
    end)
  end
end
