# edge_admin/lib/edge_admin/proxy_servers/routing.ex
defmodule EdgeAdmin.ProxyServers.Routing do
  @moduledoc """
  Resolves Admin proxy usernames into direct or chained routing targets.

  Authentication is intentionally kept separate; this module only interprets
  the username and looks up a node when proxy chaining is requested.
  """

  require Logger

  @nodes_module Application.compile_env(:edge_admin, :nodes_module, EdgeAdmin.Nodes)
  @compile {:no_warn_undefined, @nodes_module}

  @doc """
  Parses a proxy username into direct routing or a node-backed chain route.
  """
  @spec parse(String.t()) ::
          {:ok, :direct}
          | {:ok, :chain, map()}
          | {:error, :invalid_dns_format | :node_not_found | :cluster_not_found}
  def parse(""), do: {:ok, :direct}
  def parse("_"), do: {:ok, :direct}
  def parse(node_dns), do: find_node_by_dns(node_dns)

  defp find_node_by_dns(node_dns) do
    domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    pattern = ~r/^node-(.+)\.(cluster-[^.]+)\.#{Regex.escape(domain)}$/

    case Regex.run(pattern, node_dns) do
      [_, identifier, network_name] ->
        cluster_name = String.replace_prefix(network_name, "cluster-", "")
        lookup_node_in_cluster(cluster_name, identifier, node_dns)

      nil ->
        Logger.warning("Invalid DNS format for proxy chaining: #{node_dns}")
        {:error, :invalid_dns_format}
    end
  end

  defp lookup_node_in_cluster(cluster_name, identifier, node_dns) do
    case @nodes_module.list_proxy_chain_identifiers(cluster_name) do
      {:ok, identifiers_map} ->
        case Map.get(identifiers_map, identifier) do
          nil ->
            Logger.warning("Node not found for proxy chaining: #{node_dns}")
            {:error, :node_not_found}

          node ->
            Logger.info("Proxy chaining via node: #{node_dns}")
            {:ok, :chain, node}
        end

      {:error, :not_found} ->
        Logger.warning("Cluster not found for proxy chaining: #{cluster_name}")
        {:error, :cluster_not_found}
    end
  end
end
