# edge_admin/lib/edge_admin/mcp/tools/nodes/create_enrollment_key.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.CreateEnrollmentKey do
  @moduledoc "Create an enrollment key for a cluster. Agents use this key to join the VPN mesh."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.EnrollmentKeyData
  alias EdgeAdmin.Nodes

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
            {:reply, Response.error(Response.tool(), "Failed to create enrollment key: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{params.cluster_name} not found"), frame}
    end
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
