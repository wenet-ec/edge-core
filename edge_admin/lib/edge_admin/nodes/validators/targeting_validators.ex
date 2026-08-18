# edge_admin/lib/edge_admin/nodes/validators/targeting_validators.ex
defmodule EdgeAdmin.Nodes.Validators.TargetingValidators do
  @moduledoc "Pure validators for the shared node-targeting shape."

  @types ["all", "nodes", "clusters"]

  @spec valid_type?(term()) :: boolean()
  def valid_type?(type), do: type in @types

  @spec requirement_error(term(), term(), term()) :: :ok | {:error, atom(), String.t()}
  def requirement_error("nodes", node_ids, _cluster_names) when is_list(node_ids) and node_ids != [], do: :ok

  def requirement_error("clusters", _node_ids, cluster_names) when is_list(cluster_names) and cluster_names != [],
    do: :ok

  def requirement_error("nodes", _node_ids, _cluster_names),
    do: {:error, :node_ids, "is required when targeting_type is 'nodes'"}

  def requirement_error("clusters", _node_ids, _cluster_names),
    do: {:error, :cluster_names, "is required when targeting_type is 'clusters'"}

  def requirement_error(_type, _node_ids, _cluster_names), do: :ok

  @spec errors(term()) :: [String.t()]
  def errors(targeting) when is_map(targeting) do
    type = Map.get(targeting, "type") || Map.get(targeting, :type)
    node_ids = Map.get(targeting, "node_ids") || Map.get(targeting, :node_ids)
    cluster_names = Map.get(targeting, "cluster_names") || Map.get(targeting, :cluster_names)

    type_errors = if valid_type?(type), do: [], else: ["type must be all, nodes, or clusters"]

    requirement_errors =
      case requirement_error(type, node_ids, cluster_names) do
        :ok -> []
        {:error, _field, message} -> [message]
      end

    type_errors ++ requirement_errors
  end

  def errors(_targeting), do: ["must be an object"]
end
