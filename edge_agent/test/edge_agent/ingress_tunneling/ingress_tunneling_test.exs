# edge_agent/test/edge_agent/ingress_tunneling/ingress_tunneling_test.exs
defmodule EdgeAgent.IngressTunnelingTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.IngressTunneling
  alias EdgeAgent.IngressTunneling.Identity
  alias EdgeAgent.Settings

  test "upserts desired state when its public key matches the Agent identity" do
    assert {:ok, public_key} = Identity.public_key()
    desired_state = %{"ingress_public_key" => public_key, "peers" => []}

    assert {:ok, ^desired_state} = IngressTunneling.upsert_ingress_tunneling(desired_state)
    assert Settings.get_ingress_tunneling() == desired_state
  end

  test "rejects desired state for a different Agent identity" do
    desired_state = %{"ingress_public_key" => String.duplicate("A", 44), "peers" => []}

    assert {:error, {:conflict, "ingress_public_key does not match Agent identity"}} =
             IngressTunneling.upsert_ingress_tunneling(desired_state)

    assert Settings.get_ingress_tunneling() == nil
  end
end
