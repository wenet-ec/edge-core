# edge_agent/test/edge_agent/diagnostics/wireguard_interface_test.exs
defmodule EdgeAgent.Diagnostics.WireguardInterfaceTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Diagnostics.WireguardInterface

  test "passes for an up interface with a VPN address and route" do
    assert {:ok, details} =
             WireguardInterface.assess(
               %{"operstate" => "UNKNOWN", "flags" => ["POINTOPOINT", "NOARP", "UP", "LOWER_UP"]},
               %{"addr_info" => [%{"local" => "100.64.0.2", "prefixlen" => 16, "scope" => "global"}]},
               [%{"dst" => "100.64.0.0/16", "protocol" => "kernel"}]
             )

    assert details.interface == "netmaker"
    assert details.addresses == ["100.64.0.2/16"]
    assert details.routes == [%{destination: "100.64.0.0/16", protocol: "kernel"}]
  end

  test "fails when the interface is down" do
    assert {:error, "WireGuard interface is not up", _details} =
             WireguardInterface.assess(%{"operstate" => "DOWN", "flags" => []}, %{"addr_info" => []}, [])
  end

  test "warns when the interface has no routes" do
    assert {:warn, "WireGuard interface has no routes", _details} =
             WireguardInterface.assess(
               %{"operstate" => "UNKNOWN", "flags" => ["UP"]},
               %{"addr_info" => [%{"local" => "100.64.0.2", "prefixlen" => 16, "scope" => "global"}]},
               []
             )
  end
end
