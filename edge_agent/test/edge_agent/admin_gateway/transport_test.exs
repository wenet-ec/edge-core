# edge_agent/test/edge_agent/admin_gateway/transport_test.exs
defmodule EdgeAgent.AdminGateway.TransportTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.AdminGateway.Transport

  test "VPN URLs precede configured fallback URLs" do
    assert Transport.urls_to_try(["vpn-1", "vpn-2"], ["fallback-1", "fallback-2"]) ==
             ["vpn-1", "vpn-2", "fallback-1", "fallback-2"]
  end

  test "duplicate URLs are attempted once, preserving first occurrence" do
    assert Transport.urls_to_try(["vpn", "shared"], ["shared", "fallback"]) ==
             ["vpn", "shared", "fallback"]
  end
end
