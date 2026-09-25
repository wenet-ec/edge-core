# edge_admin/test/edge_admin/ingress_tunneling/schemas/tunnel_connection_test.exs
defmodule EdgeAdmin.IngressTunneling.Schemas.TunnelConnectionTest do
  use ExUnit.Case, async: true

  import EdgeAdmin.Test.ChangesetAssertions, only: [errors_on: 1]

  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        tunnel_client_id: "11111111-2222-3333-4444-555555555555",
        node_id: "22222222-3333-4444-5555-666666666666",
        ingress_ipv4_address: "10.240.0.1/32",
        ingress_ipv6_address: "fd20:240::1/128",
        tunnel_ipv4_address: "10.240.0.2/32",
        tunnel_ipv6_address: "fd20:240::2/128"
      },
      overrides
    )
  end

  test "accepts a connection with one IPv4 /32 and one IPv6 /128" do
    assert TunnelConnection.changeset(%TunnelConnection{}, valid_attrs()).valid?
  end

  test "rejects address prefixes broader than one Tunnel address" do
    changeset =
      TunnelConnection.changeset(
        %TunnelConnection{},
        valid_attrs(%{
          ingress_ipv4_address: "10.240.0.1/24",
          ingress_ipv6_address: "fd20:240::1/64",
          tunnel_ipv4_address: "10.240.0.2/24",
          tunnel_ipv6_address: "fd20:240::2/64"
        })
      )

    refute changeset.valid?
    assert "must be an IPv4 address with a /32 prefix" in errors_on(changeset).ingress_ipv4_address
    assert "must be an IPv6 address with a /128 prefix" in errors_on(changeset).ingress_ipv6_address
    assert "must be an IPv4 address with a /32 prefix" in errors_on(changeset).tunnel_ipv4_address
    assert "must be an IPv6 address with a /128 prefix" in errors_on(changeset).tunnel_ipv6_address
  end

  test "declares address allocation constraints within one Ingress realm" do
    changeset = TunnelConnection.changeset(%TunnelConnection{}, valid_attrs())

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.field == :node_id and constraint.type == :unique
           end)
  end
end
