# edge_admin/test/edge_admin/ingress_tunneling/schemas/tunnel_client_test.exs
defmodule EdgeAdmin.IngressTunneling.Schemas.TunnelClientTest do
  use ExUnit.Case, async: true

  import EdgeAdmin.Test.ChangesetAssertions, only: [errors_on: 1]

  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient

  @wireguard_key Base.encode64(:binary.copy(<<1>>, 32))

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{public_key: @wireguard_key, private_key: @wireguard_key}, overrides)
  end

  test "accepts a canonical Tunnel WireGuard keypair" do
    assert TunnelClient.changeset(%TunnelClient{}, valid_attrs()).valid?
  end

  test "requires canonical WireGuard key material" do
    changeset = TunnelClient.changeset(%TunnelClient{}, valid_attrs(%{private_key: "not-a-wireguard-key"}))

    refute changeset.valid?
    assert "must be a canonical base64-encoded WireGuard key" in errors_on(changeset).private_key
  end

  test "declares the database uniqueness constraint for the public key" do
    changeset = TunnelClient.changeset(%TunnelClient{}, valid_attrs())

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.field == :public_key and constraint.type == :unique
           end)
  end
end
