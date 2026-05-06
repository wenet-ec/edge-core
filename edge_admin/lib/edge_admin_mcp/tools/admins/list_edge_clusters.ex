# edge_admin/lib/edge_admin_mcp/tools/admins/list_edge_clusters.ex
defmodule EdgeAdminMcp.Tools.Admins.ListEdgeClusters do
  @moduledoc """
  List all edge clusters currently assigned to admin instances, grouped
  by owning admin.

  Returns a map keyed by admin name; each value is a map of the clusters
  that admin owns:

      %{
        "admin-7k3m9p2nq8r4" => %{
          "cluster-prod" => %{...},
          "cluster-staging" => %{...}
        },
        "admin-x4j8h2mn3p9q" => %{...}
      }

  Use `list_orphaned_clusters` for clusters with no owner.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  @impl true
  def title, do: "List Edge Clusters (Admin View)"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_edge_clusters()), frame}
  end
end
