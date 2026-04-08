# edge_admin/lib/edge_admin/nodes/checks/same_cluster_check.ex
defmodule EdgeAdmin.Nodes.Checks.SameClusterCheck do
  @moduledoc """
  Checks that a node is not already in the target cluster.

  Prevents a no-op cluster change request from proceeding.
  """

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  @spec check(Node.t(), Cluster.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Node{cluster_id: same_id}, %Cluster{id: same_id}) do
    {:error, {:conflict, "node is already in this cluster"}}
  end

  def check(%Node{}, %Cluster{}), do: :ok
end
