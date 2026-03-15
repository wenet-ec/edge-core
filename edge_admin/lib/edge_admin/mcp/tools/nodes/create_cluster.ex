# edge_admin/lib/edge_admin/mcp/tools/nodes/create_cluster.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.CreateCluster do
  @moduledoc "Create a new edge cluster. ipv4_range is auto-assigned if omitted. node_limit caps how many nodes can enroll."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.ClusterData
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
      {:ok, cluster} ->
        {:reply, Response.json(Response.tool(), ClusterData.data(cluster)), frame}

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
