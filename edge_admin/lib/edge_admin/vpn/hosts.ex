# edge_admin/lib/edge_admin/vpn/hosts.ex
defmodule EdgeAdmin.Vpn.Hosts do
  @moduledoc "Edge VPN host inventory and hostname resolution."

  alias EdgeAdmin.Vpn.Api, as: VpnApi
  alias Nexmaker.Api.Hosts, as: NexmakerHosts
  alias Nexmaker.Api.Nodes, as: NexmakerNodes

  require Logger

  @spec get_host_id(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :host_not_found | :not_found | :service_unavailable}
  def get_host_id(hostname, opts \\ []) do
    network_name = Keyword.get(opts, :network_name)

    Logger.debug(
      "Looking for Edge VPN host with name: #{hostname}" <>
        if(network_name, do: " in network: #{network_name}", else: "")
    )

    with {:ok, hosts} <- list_hosts(),
         {:ok, nodes} <- list_nodes_for_host_resolution(network_name) do
      hosts = filter_hosts_for_host_resolution(hosts, nodes, network_name)

      Logger.debug("Retrieved #{length(hosts)} Edge VPN hosts")

      case select_host_id(hosts, nodes, hostname) do
        nil ->
          Logger.debug("No Edge VPN host found with name: #{hostname}")
          {:error, :host_not_found}

        host_id ->
          Logger.debug("Found Edge VPN host ID: #{host_id} for name: #{hostname}")
          {:ok, host_id}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to resolve Edge VPN host ID for #{hostname}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  @spec select_host_id([map()], [map()], String.t()) :: String.t() | nil
  def select_host_id(hosts, nodes, hostname) do
    matching_hosts = Enum.filter(hosts, &(&1["name"] == hostname))

    case matching_hosts do
      [] ->
        nil

      [host] ->
        host["id"]

      _ ->
        node_by_host_id = Map.new(nodes, fn node -> {node["hostid"], node} end)

        matching_hosts
        |> Enum.max_by(&candidate_rank(&1, node_by_host_id), fn -> nil end)
        |> case do
          nil -> nil
          host -> host["id"]
        end
    end
  end

  defp list_nodes_for_host_resolution(nil), do: {:ok, []}

  defp list_nodes_for_host_resolution(network_name),
    do: network_name |> NexmakerNodes.list() |> VpnApi.normalize_error()

  defp filter_hosts_for_host_resolution(hosts, _nodes, nil), do: hosts

  defp filter_hosts_for_host_resolution(hosts, nodes, _network_name) do
    host_ids_in_network = MapSet.new(nodes, & &1["hostid"])
    Enum.filter(hosts, &MapSet.member?(host_ids_in_network, &1["id"]))
  end

  defp candidate_rank(host, node_by_host_id) do
    node = Map.get(node_by_host_id, host["id"])

    {
      if(node, do: 1, else: 0),
      if(node && node["connected"], do: 1, else: 0),
      node_timestamp(node, "lastmodified"),
      node_timestamp(node, "lastcheckin"),
      node_timestamp(node, "lastpeerupdate"),
      host["id"]
    }
  end

  defp node_timestamp(nil, _field), do: -1

  defp node_timestamp(node, field) do
    case Map.get(node, field) do
      value when is_integer(value) -> value
      _ -> -1
    end
  end

  @spec list_hosts() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_hosts, do: fetch_all_hosts()

  defp fetch_all_hosts(page \\ 1, acc \\ []) do
    case VpnApi.normalize_error(NexmakerHosts.list(page: page, per_page: 100)) do
      {:ok, %{"data" => hosts, "total_pages" => total_pages}} ->
        all = acc ++ hosts
        if page >= total_pages, do: {:ok, all}, else: fetch_all_hosts(page + 1, all)

      {:ok, %{"data" => hosts}} ->
        {:ok, acc ++ hosts}

      error ->
        error
    end
  end

  @spec get_host(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_host(host_id), do: host_id |> NexmakerHosts.get() |> VpnApi.normalize_error()

  @spec delete_host(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_host(host_id), do: host_id |> NexmakerHosts.delete() |> VpnApi.normalize_error()
end
