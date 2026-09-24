# edge_admin/lib/edge_admin/ingress_tunneling/checks/ingress_identity_check.ex
defmodule EdgeAdmin.IngressTunneling.Checks.IngressIdentityCheck do
  @moduledoc "Checks that a node has an Ingress WireGuard identity."

  alias EdgeAdmin.Nodes.Schemas.Node

  @doc "Rejects nodes without an Ingress WireGuard public key."
  @spec check(Node.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Node{ingress_public_key: key}) when is_binary(key) and key != "", do: :ok

  def check(%Node{}), do: {:error, {:conflict, "node has no Ingress WireGuard identity"}}
end
