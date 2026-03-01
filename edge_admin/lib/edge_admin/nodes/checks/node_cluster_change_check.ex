# edge_admin/lib/edge_admin/nodes/checks/node_cluster_change_check.ex
defmodule EdgeAdmin.Nodes.Checks.NodeClusterChangeCheck do
  @moduledoc """
  Precondition check for changing a node's cluster assignment.

  Passes when the target cluster is different from the node's current cluster.
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
