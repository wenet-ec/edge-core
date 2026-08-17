# edge_admin/lib/edge_admin/proxy_servers/admin_tunnel/config.ex
defmodule EdgeAdmin.ProxyServers.AdminTunnel.Config do
  @moduledoc "Configuration for the private Admin-to-Admin TCP tunnel."

  alias EdgeAdmin.Vpn

  @doc "Returns the Admin-to-Admin TCP tunnel port."
  def port do
    Application.get_env(:edge_admin, :admin_tcp_tunnel_port, 45_207)
  end

  @doc "Returns the shared Admin-to-Admin tunnel handshake secret."
  def secret do
    Application.get_env(:edge_admin, :admin_tcp_tunnel_secret, "edge_admin_default_tcp_tunnel_secret")
  end

  @doc "Returns available local addresses on the Admin-cluster VPN network."
  def bind_addresses do
    admin_cluster_name = Application.fetch_env!(:edge_admin, :admin_cluster_name)

    with {:ok, nodes} <- Vpn.read_local_vpn_nodes(),
         node when is_map(node) <- Enum.find(nodes, &(&1["network"] == admin_cluster_name and &1["connected"] == true)) do
      addresses = Enum.flat_map([{:inet, node["ipv4_addr"]}, {:inet6, node["ipv6_addr"]}], &parse_address/1)

      if addresses == [], do: {:error, :admin_cluster_address_not_found}, else: {:ok, addresses}
    else
      nil -> {:error, :admin_cluster_address_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_admin_cluster_state}
    end
  end

  defp parse_address({_family, address}) when not is_binary(address) or address == "", do: []

  defp parse_address({family, address}) do
    ip_string = address |> String.split("/", parts: 2) |> hd()

    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_address} -> [{family, ip_address}]
      {:error, _reason} -> []
    end
  end
end
