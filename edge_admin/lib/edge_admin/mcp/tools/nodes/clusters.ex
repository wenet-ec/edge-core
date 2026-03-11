# edge_admin/lib/edge_admin/mcp/tools/nodes/clusters.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListClusters do
  @moduledoc "List all edge clusters. Each cluster is an isolated VPN network that groups nodes together."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
  end

  @impl true
  def execute(params, frame) do
    case Nodes.list_clusters(%{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}) do
      {:ok, {clusters, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           clusters: Enum.map(clusters, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list clusters: #{inspect(reason)}"), frame}
    end
  end

  defp format(c),
    do: %{
      name: c.name,
      ipv4_range: c.ipv4_range,
      node_count: c.node_count,
      node_limit: c.node_limit,
      inserted_at: c.inserted_at
    }
end

defmodule EdgeAdmin.MCP.Tools.Nodes.GetCluster do
  @moduledoc "Get a cluster by name."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    case Nodes.get_cluster(name) do
      {:ok, c} ->
        {:reply,
         Response.json(Response.tool(), %{
           name: c.name,
           ipv4_range: c.ipv4_range,
           node_count: c.node_count,
           node_limit: c.node_limit,
           inserted_at: c.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.CreateCluster do
  @moduledoc "Create a new edge cluster. ipv4_range is auto-assigned if omitted. node_limit caps how many nodes can enroll."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :name, :string, required: true
    field :ipv4_range, :string
    field :node_limit, :integer
  end

  @impl true
  def execute(params, frame) do
    attrs =
      %{"name" => params.name}
      |> maybe_put("ipv4_range", params[:ipv4_range])
      |> maybe_put("node_limit", params[:node_limit])

    case Nodes.create_cluster(attrs) do
      {:ok, c} ->
        {:reply,
         Response.json(Response.tool(), %{
           name: c.name,
           ipv4_range: c.ipv4_range,
           node_limit: c.node_limit,
           inserted_at: c.inserted_at
         }), frame}

      {:error, :service_unavailable} ->
        {:reply, Response.error(Response.tool(), "Netmaker VPN unavailable — cluster not created"), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), "Validation failed: #{format_errors(changeset)}"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)

  defp format_errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> inspect()
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.UpdateCluster do
  @moduledoc "Update a cluster's node_limit. Pass null to remove the limit."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
    field :node_limit, :integer
  end

  @impl true
  def execute(%{cluster_name: name} = params, frame) do
    case Nodes.get_cluster(name) do
      {:ok, cluster} ->
        case Nodes.update_cluster(cluster, %{"node_limit" => params[:node_limit]}) do
          {:ok, c} -> {:reply, Response.json(Response.tool(), %{name: c.name, node_limit: c.node_limit}), frame}
          {:error, reason} -> {:reply, Response.error(Response.tool(), "Update failed: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.DeleteCluster do
  @moduledoc "Delete a cluster and its VPN network. All nodes lose connectivity. Irreversible."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    with {:ok, cluster} <- Nodes.get_cluster(name),
         {:ok, _} <- Nodes.delete_cluster(cluster) do
      {:reply, Response.text(Response.tool(), "Cluster #{name} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
