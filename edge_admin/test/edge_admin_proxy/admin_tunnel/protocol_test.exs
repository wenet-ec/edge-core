# edge_admin/test/edge_admin_proxy/admin_tunnel/protocol_test.exs
defmodule EdgeAdminProxy.AdminTunnel.ProtocolTest do
  use ExUnit.Case, async: true

  alias EdgeAdminProxy.AdminTunnel.Protocol

  @secret "test-admin-tunnel-secret"

  describe "the authenticated handshake" do
    test "accepts a handshake built with the same secret" do
      request = Protocol.build_handshake(@secret, "node-a.cluster-test.nm.internal", 8080)

      assert {:ok, "node-a.cluster-test.nm.internal", 8080} =
               Protocol.validate_handshake(@secret, request)
    end

    test "rejects a handshake signed with a different secret" do
      request = Protocol.build_handshake(@secret, "node-a.cluster-test.nm.internal", 8080)

      assert {:error, :unauthorized} = Protocol.validate_handshake("wrong-secret", request)
    end

    test "rejects a tampered target" do
      request = Protocol.build_handshake(@secret, "node-a.cluster-test.nm.internal", 8080)
      tampered = replace_target_port(request, 9090)

      assert {:error, :unauthorized} = Protocol.validate_handshake(@secret, tampered)
    end

    test "rejects malformed and truncated handshakes" do
      request = Protocol.build_handshake(@secret, "node-a.cluster-test.nm.internal", 8080)

      assert {:error, :invalid_handshake} = Protocol.validate_handshake(@secret, <<>>)

      assert {:error, :invalid_handshake} =
               Protocol.validate_handshake(@secret, binary_part(request, 0, byte_size(request) - 1))

      assert {:error, :invalid_handshake} = Protocol.validate_handshake(@secret, "not-a-tunnel")
    end

    test "rejects an empty target and port zero" do
      empty_target = Protocol.build_handshake(@secret, "", 8080)
      zero_port = Protocol.build_handshake(@secret, "node-a.cluster-test.nm.internal", 0)

      assert {:error, :invalid_target} = Protocol.validate_handshake(@secret, empty_target)
      assert {:error, :invalid_target} = Protocol.validate_handshake(@secret, zero_port)
    end
  end

  defp replace_target_port(request, port) do
    prefix_size = byte_size(request) - 2 - 32
    prefix = binary_part(request, 0, prefix_size)
    mac = binary_part(request, byte_size(request) - 32, 32)
    <<prefix::binary, port::16, mac::binary>>
  end
end
