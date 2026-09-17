# edge_admin/lib/edge_admin/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAdmin.IngressTunneling do
  @moduledoc """
  Public domain boundary for Core-managed Ingress Tunneling.

  The context owns Tunnel client identities, their selected Ingress Node
  connections, provisioning artifacts, and Agent Ingress desired state. This
  initial module establishes the boundary; action APIs are added alongside
  their forms, checks, resources, and workflows.
  """
end
