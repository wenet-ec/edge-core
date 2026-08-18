# edge_admin/lib/edge_admin/admin_gateway/reconciliation.ex
defmodule EdgeAdmin.AdminGateway.Reconciliation do
  @moduledoc "Pure planner for Admin Gateway membership changes."

  @type plan :: %{
          to_join: MapSet.t(),
          to_leave: MapSet.t(),
          retained: MapSet.t()
        }

  @doc "Calculates Gateway joins, leaves, and retained clusters."
  @spec plan(Enumerable.t(), Enumerable.t()) :: plan()
  def plan(current_clusters, assigned_clusters) do
    current = MapSet.new(current_clusters)
    assigned = MapSet.new(assigned_clusters)

    %{
      to_join: MapSet.difference(assigned, current),
      to_leave: MapSet.difference(current, assigned),
      retained: MapSet.intersection(current, assigned)
    }
  end
end
