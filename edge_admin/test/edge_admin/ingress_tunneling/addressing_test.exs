# edge_admin/test/edge_admin/ingress_tunneling/addressing_test.exs
defmodule EdgeAdmin.IngressTunneling.AddressingTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.Addressing

  test "records the first usable address for the Ingress and the next address for the Tunnel Client" do
    assert {:ok,
            %{
              ingress_ipv4_address: "10.240.0.1/32",
              ingress_ipv6_address: "fd20:240::1/128",
              tunnel_ipv4_address: "10.240.0.2/32",
              tunnel_ipv6_address: "fd20:240::2/128"
            }} =
             Addressing.allocate([], [], ["10.240.0.0/30"], ["fd20:240::/126"])
  end

  test "allocates addresses after the Ingress-reserved IPv4 and IPv6 addresses" do
    assert {:ok, "10.240.0.2/32"} = Addressing.next_ipv4_address([], ["10.240.0.0/30"])
    assert {:ok, "fd20:240::2/128"} = Addressing.next_ipv6_address([], ["fd20:240::/126"])
  end

  test "skips addresses already allocated within one Ingress realm" do
    assert {:ok, "10.240.0.3/32"} =
             Addressing.next_ipv4_address(["10.240.0.2/32"], ["10.240.0.0/30"])

    assert {:ok, "fd20:240::3/128"} =
             Addressing.next_ipv6_address(["fd20:240::2/128"], ["fd20:240::/126"])
  end

  test "reports exhaustion after every allocatable address in a pool is used" do
    assert {:error, {:conflict, reason}} =
             Addressing.next_ipv4_address(["10.240.0.2/32", "10.240.0.3/32"], ["10.240.0.0/30"])

    assert reason =~ "no IPv4 addresses remain"
  end

  test "uses the next configured pool after an earlier pool is exhausted" do
    assert {:ok, "10.241.0.2/32"} =
             Addressing.next_ipv4_address(
               ["10.240.0.2/32", "10.240.0.3/32"],
               ["10.240.0.0/30", "10.241.0.0/30"]
             )
  end
end
