# edge_admin/lib/edge_admin_mcp/tools/nodes/create_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateCluster do
  @moduledoc "Create a new edge cluster. ipv4_range is auto-assigned if omitted. node_limit caps how many nodes can enroll."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.ClusterData

  @impl true
  def title, do: "Create Cluster"
  @impl true
  def annotations, do: %{"destructiveHint" => false}

  schema do
    field :name, {:required, :string}, min_length: 1
    field :ipv4_range, :string
    field :node_limit, :integer, min: 1
  end

  @impl true
  def execute(params, frame) do
    attrs =
      %{"name" => params.name}
      |> put_if("ipv4_range", params[:ipv4_range])
      |> put_if("node_limit", params[:node_limit])

    case Nodes.create_cluster(attrs) do
      {:ok, cluster} ->
        {:reply, Response.json(Response.tool(), ClusterData.data(cluster)), frame}

      {:error, :service_unavailable} ->
        {:reply, error_response(:service_unavailable), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
