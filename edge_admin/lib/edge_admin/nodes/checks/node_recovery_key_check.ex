# edge_admin/lib/edge_admin/nodes/checks/node_recovery_key_check.ex
defmodule EdgeAdmin.Nodes.Checks.NodeRecoveryKeyCheck do
  @moduledoc """
  Authorizes recovery of an existing node.

  The supplied key must match the node's stored recovery key and must identify
  the node's canonical cluster.
  """

  alias EdgeAdmin.Nodes.Schemas.Node

  @doc "Authorizes recovery when the supplied key matches the node and cluster."
  @spec check(Node.t(), String.t() | nil, String.t()) :: :ok | {:error, :unauthorized}
  def check(%Node{recovery_key: stored_key}, recovery_key, cluster_name) do
    if matches?(recovery_key, stored_key) and recovery_cluster_name(recovery_key) == cluster_name do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp matches?(provided, stored) when is_binary(provided) and provided != "" and is_binary(stored) and stored != "" do
    Plug.Crypto.secure_compare(provided, stored)
  end

  defp matches?(_provided, _stored), do: false

  defp recovery_cluster_name(recovery_key) do
    with {:ok, json} <- Base.decode64(recovery_key),
         {:ok, %{"cluster_name" => cluster_name}} <- JSON.decode(json),
         true <- is_binary(cluster_name) and cluster_name != "" do
      cluster_name
    else
      _ -> nil
    end
  end
end
