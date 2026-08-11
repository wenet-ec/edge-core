# edge_admin/lib/edge_admin/nodes/resources/proxy.ex
defmodule EdgeAdmin.Nodes.Resources.Proxy do
  @moduledoc "Proxy-specific node identifier lookup."

  import Ecto.Query, warn: false

  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @doc "Lists node IDs and aliases accepted by proxy-chain authentication."
  @spec list_chain_identifiers(String.t()) :: {:ok, map()} | {:error, :not_found}
  def list_chain_identifiers(cluster_name) do
    rows =
      Repo.all(
        from c in ClusterQueries.active(),
          join: n in assoc(c, :nodes),
          left_join: a in Alias,
          on: a.node_id == n.id,
          where: c.name == ^cluster_name,
          select: %{
            id: n.id,
            proxy_password: n.proxy_password,
            http_proxy_port: n.http_proxy_port,
            socks5_proxy_port: n.socks5_proxy_port,
            cluster_name: c.name,
            alias_name: a.name
          }
      )

    case rows do
      [] ->
        if Repo.exists?(ClusterQueries.active_by_name(cluster_name)), do: {:ok, %{}}, else: {:error, :not_found}

      _ ->
        identifiers =
          Enum.reduce(rows, %{}, fn row, acc ->
            node = %Node{
              id: row.id,
              proxy_password: row.proxy_password,
              http_proxy_port: row.http_proxy_port,
              socks5_proxy_port: row.socks5_proxy_port,
              cluster: %Cluster{name: row.cluster_name}
            }

            acc = Map.put_new(acc, row.id, node)
            if row.alias_name, do: Map.put(acc, row.alias_name, node), else: acc
          end)

        {:ok, identifiers}
    end
  end
end
