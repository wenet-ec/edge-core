# edge_admin/lib/edge_admin_mcp/tools/nodes/create_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateEnrollmentKey do
  @moduledoc "Create an enrollment key for a cluster. Agents use this key to join the VPN mesh."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.EnrollmentKeyData

  schema do
    field :cluster_name, {:required, :string}, min_length: 1
    field :uses_remaining, :integer, min: 1
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_cluster(params.cluster_name) do
      {:ok, cluster} ->
        attrs =
          %{}
          |> put_if("uses_remaining", params[:uses_remaining])
          |> put_if("expired_at", params[:expired_at])

        case Nodes.create_enrollment_key(cluster, attrs) do
          {:ok, key} ->
            {:reply, Response.json(Response.tool(), EnrollmentKeyData.data(key)), frame}

          {:error, reason} ->
            {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "Cluster #{params.cluster_name} not found")),
         frame}
    end
  end
end
