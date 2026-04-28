# edge_admin/lib/edge_admin_mcp/tools/admins/list_admin_clusters.ex
defmodule EdgeAdminMcp.Tools.Admins.ListAdminClusters do
  @moduledoc """
  List every admin cluster Netmaker knows about, with each cluster's admins.

  Includes admins this instance is not a member of (cross-cluster visibility) and
  may include stale entries — useful for spotting zombie admins by checking the
  `last_checked_in` and `status` fields.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins

  @impl true
  def title, do: "List All Admin Clusters"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    case Admins.list_admin_clusters() do
      {:ok, admin_clusters} ->
        payload = %{
          admin_clusters: admin_clusters,
          cluster_count: length(admin_clusters)
        }

        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, _reason} ->
        {:reply, error_response(:service_unavailable), frame}
    end
  end
end
