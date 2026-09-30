# edge_admin/lib/edge_admin/ingress_tunneling/desired_state.ex
defmodule EdgeAdmin.IngressTunneling.DesiredState do
  @moduledoc """
  Builds the complete Ingress Tunneling snapshot for an Agent node from
  the current Tunnel Client and Tunnel Connection records. The result includes
  the node's ingress identity, cluster VPN settings, and one peer entry for
  each connection owned by the node.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @doc "Builds the snapshot for an existing node."
  @spec build(String.t()) :: {:ok, map()} | {:error, :not_found}
  def build(node_id) do
    case Repo.get(Node, node_id) do
      nil ->
        {:error, :not_found}

      node ->
        node = Repo.preload(node, :cluster)
        {:ok, state(node, connections_for_node(node.id))}
    end
  end

  defp connections_for_node(node_id) do
    Repo.all(
      from(connection in TunnelConnection,
        where: connection.node_id == ^node_id,
        order_by: [asc: connection.inserted_at],
        preload: [:tunnel_client]
      )
    )
  end

  defp state(node, connections) do
    cluster = node.cluster

    %{
      "ingress_public_key" => node.ingress_public_key,
      "ingress_ipv4_addresses" => ingress_addresses(connections, :ingress_ipv4_address),
      "ingress_ipv6_addresses" => ingress_addresses(connections, :ingress_ipv6_address),
      "vpn_dns_suffix" => Cluster.vpn_domain(cluster),
      "vpn_ipv4_range" => cluster.ipv4_range,
      "vpn_ipv6_range" => cluster.ipv6_range,
      "core_derp_map_urls" => Application.get_env(:edge_admin, :core_derp_map_urls, []),
      "peers" => Enum.map(connections, &peer/1)
    }
  end

  defp ingress_addresses(connections, field),
    do: connections |> Enum.map(&Map.fetch!(&1, field)) |> Enum.uniq() |> Enum.sort()

  defp peer(connection) do
    %{
      "tunnel_connection_id" => connection.id,
      "tunnel_public_key" => connection.tunnel_client.public_key,
      "tunnel_ipv4_address" => connection.tunnel_ipv4_address,
      "tunnel_ipv6_address" => connection.tunnel_ipv6_address,
      "allowed_ips" => [connection.tunnel_ipv4_address, connection.tunnel_ipv6_address]
    }
  end
end
