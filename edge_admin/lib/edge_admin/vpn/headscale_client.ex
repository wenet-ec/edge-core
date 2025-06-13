# edge_admin/lib/edge_admin/vpn/headscale_client.ex
defmodule EdgeAdmin.VPN.HeadscaleClient do
  @moduledoc """
  HTTP client for communicating with VPN wrapper service.
  """

  require Logger

  defp wrapper_url do
    Application.get_env(:edge_admin, :vpn_wrapper_url, "http://edge_vpn:8081")
  end

  def get_node_by_hostname(vpn_hostname) do
    url = "#{wrapper_url()}/api/v1/node?user=edge-nodes"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"nodes" => nodes}}} ->
        find_node_by_name(nodes, vpn_hostname)

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp find_node_by_name(nodes, vpn_hostname) do
    case Enum.find(nodes, fn node -> node["name"] == vpn_hostname end) do
      nil ->
        {:error, :node_not_found}

      node ->
        vpn_info = %{
          vpn_ip: get_primary_ip(node["ipAddresses"]),
          vpn_hostname: node["name"],
          online: node["online"],
          last_seen: node["lastSeen"]
        }
        {:ok, vpn_info}
    end
  end

  defp get_primary_ip([ip | _]), do: ip
  defp get_primary_ip([]), do: nil
end
