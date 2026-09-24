# edge_admin/test/edge_admin/ingress_tunneling/checks/ingress_identity_check_test.exs
defmodule EdgeAdmin.IngressTunneling.Checks.IngressIdentityCheckTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.Checks.IngressIdentityCheck
  alias EdgeAdmin.Nodes.Schemas.Node

  test "accepts a node with an Ingress WireGuard public key" do
    assert :ok = IngressIdentityCheck.check(%Node{ingress_public_key: "public-key"})
  end

  test "rejects a node without an Ingress WireGuard public key" do
    assert {:error, {:conflict, "node has no Ingress WireGuard identity"}} =
             IngressIdentityCheck.check(%Node{ingress_public_key: nil})
  end

  test "rejects a blank Ingress WireGuard public key" do
    assert {:error, {:conflict, "node has no Ingress WireGuard identity"}} =
             IngressIdentityCheck.check(%Node{ingress_public_key: ""})
  end
end
