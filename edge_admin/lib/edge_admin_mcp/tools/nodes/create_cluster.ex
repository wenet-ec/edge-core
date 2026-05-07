# edge_admin/lib/edge_admin_mcp/tools/nodes/create_cluster.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateCluster do
  @moduledoc """
  Create a new edge cluster.

  - `name` — required. Lowercase alphanumeric and hyphens only, must start
    and end with alphanumeric. Max 24 characters. Examples: `prod`,
    `prod-east`, `homelab-1`. The literal `default` is reserved.
  - `ipv4_range` — optional CIDR (e.g. `100.64.1.0/24`). Auto-assigned from
    the available pool if omitted.
  - `node_limit` — optional cap on how many nodes can enroll. Omit for no
    limit.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.ClusterView

  @max_length Naming.cluster_name_max_length()
  @regex Naming.cluster_name_regex()

  @impl true
  def title, do: "Create Cluster"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => true}

  schema do
    field :name, {:required, :string}, max_length: @max_length, regex: @regex
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
        {:reply, Response.json(Response.tool(), ClusterView.render(cluster)), frame}

      {:error, :service_unavailable} ->
        {:reply, error_response(:service_unavailable), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
