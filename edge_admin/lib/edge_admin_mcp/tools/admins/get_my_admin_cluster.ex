# edge_admin/lib/edge_admin_mcp/tools/admins/get_my_admin_cluster.ex
defmodule EdgeAdminMcp.Tools.Admins.GetMyAdminCluster do
  @moduledoc """
  Get the admin cluster this admin belongs to.

  Returns the `:admin_cluster` ETS record:
  - `name` — admin cluster name
  - `total_admins` / `total_nodes` / `total_edge_capacity` — fleet-wide totals
  - `degraded` — true when total_nodes > total_edge_capacity (over capacity)
  - `topology` — list of every peer admin (incl. self) with their assigned
    edge clusters
  - `weak_leader` — alphabetically-first admin id; the LocalScheduler
    skips weak-leader-only jobs on every other admin
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Admins.Metadata

  @impl true
  def title, do: "Get This Admin's Admin Cluster"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin_cluster()), frame}
  end
end
