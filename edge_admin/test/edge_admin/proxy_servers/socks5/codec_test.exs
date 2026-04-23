# edge_admin/test/edge_admin/proxy_servers/socks5/codec_test.exs
defmodule EdgeAdmin.ProxyServers.Socks5.CodecTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ProxyServers.Socks5.Codec, as: Socks5Codec

  describe "parse_greeting/1" do
    test "parses greeting with single method" do
      # VER=5, NMETHODS=1, METHODS=[2]
      assert {:ok, [2], <<>>} = Socks5Codec.parse_greeting(<<5, 1, 2>>)
    end

    test "parses greeting with multiple methods" do
      assert {:ok, [0, 1, 2], <<>>} = Socks5Codec.parse_greeting(<<5, 3, 0, 1, 2>>)
    end

    test "returns rest when greeting is followed by more data" do
      assert {:ok, [2], <<"extra">>} = Socks5Codec.parse_greeting(<<5, 1, 2, "extra">>)
    end

    test "requests more bytes when buffer is too short" do
      assert {:need_more, _} = Socks5Codec.parse_greeting(<<5>>)
      assert {:need_more, _} = Socks5Codec.parse_greeting(<<5, 3, 0>>)
    end

    test "rejects unsupported version" do
      assert {:error, {:unsupported_version, 4}} = Socks5Codec.parse_greeting(<<4, 1, 0>>)
    end
  end

  describe "parse_connect_request/1" do
    test "parses IPv4 connect request" do
      # VER=5, CMD=1, RSV=0, ATYP=1, 10.0.0.1, port 443
      msg = <<5, 1, 0, 1, 10, 0, 0, 1, 443::16>>
      assert {:ok, {1, "10.0.0.1", 443}, <<>>} = Socks5Codec.parse_connect_request(msg)
    end

    test "parses IPv6 connect request" do
      ipv6 = <<0::112, 1::16>>
      msg = <<5, 1, 0, 4, ipv6::binary, 443::16>>

      assert {:ok, {1, "0000:0000:0000:0000:0000:0000:0000:0001", 443}, <<>>} =
               Socks5Codec.parse_connect_request(msg)
    end

    test "parses domain connect request" do
      host = "example.com"
      msg = <<5, 1, 0, 3, byte_size(host)::8, host::binary, 80::16>>
      assert {:ok, {1, "example.com", 80}, <<>>} = Socks5Codec.parse_connect_request(msg)
    end

    test "requests more bytes when domain is incomplete" do
      host = "example.com"
      # Only give first 4 of domain + length
      partial = <<5, 1, 0, 3, byte_size(host)::8, binary_part(host, 0, 4)::binary>>
      assert {:need_more, _} = Socks5Codec.parse_connect_request(partial)
    end

    test "rejects unsupported address type" do
      assert {:error, {:unsupported_address_type, 99}} =
               Socks5Codec.parse_connect_request(<<5, 1, 0, 99, "garbage">>)
    end
  end

  describe "parse_reply/1 (server reply)" do
    test "parses IPv4 success reply" do
      msg = <<5, 0, 0, 1, 127, 0, 0, 1, 43_128::16>>
      assert {:ok, {0, "127.0.0.1", 43_128}, <<>>} = Socks5Codec.parse_reply(msg)
    end

    test "parses IPv6 success reply (22 bytes total)" do
      ipv6 = <<0::112, 1::16>>
      msg = <<5, 0, 0, 4, ipv6::binary, 43_128::16>>
      assert {:ok, {0, _host, 43_128}, <<>>} = Socks5Codec.parse_reply(msg)
    end

    test "parses domain reply" do
      host = "node-a.cluster-x.nm.internal"
      msg = <<5, 0, 0, 3, byte_size(host)::8, host::binary, 80::16>>
      assert {:ok, {0, ^host, 80}, <<>>} = Socks5Codec.parse_reply(msg)
    end

    test "requests more when reply is truncated mid-address" do
      # IPv6 needs 16 bytes after ATYP, we give 8
      partial = <<5, 0, 0, 4, 0::64>>
      assert {:need_more, _} = Socks5Codec.parse_reply(partial)
    end

    test "returns error status in parsed form" do
      msg = <<5, 2, 0, 1, 0, 0, 0, 0, 0::16>>
      assert {:ok, {2, "0.0.0.0", 0}, <<>>} = Socks5Codec.parse_reply(msg)
    end
  end

  describe "parse_auth_request/1 (RFC 1929)" do
    test "parses username + password" do
      msg = <<1, 4, "user", 4, "pass">>
      assert {:ok, {"user", "pass"}, <<>>} = Socks5Codec.parse_auth_request(msg)
    end

    test "rejects non-1 auth version" do
      assert {:error, {:unsupported_auth_version, 2}} =
               Socks5Codec.parse_auth_request(<<2, 1, "u", 1, "p">>)
    end

    test "requests more when truncated" do
      assert {:need_more, _} = Socks5Codec.parse_auth_request(<<1, 10, "short">>)
    end
  end

  describe "encode_reply/3" do
    test "encodes success with IPv4 BND.ADDR" do
      binary = Socks5Codec.encode_reply(0, {127, 0, 0, 1}, 43_128)
      assert <<5, 0, 0, 1, 127, 0, 0, 1, 43_128::16>> == binary
    end

    test "encodes success with nil address as 0.0.0.0" do
      binary = Socks5Codec.encode_reply(0, nil, 0)
      assert <<5, 0, 0, 1, 0, 0, 0, 0, 0::16>> == binary
    end

    test "encodes IPv6 BND.ADDR" do
      binary = Socks5Codec.encode_reply(0, {0, 0, 0, 0, 0, 0, 0, 1}, 443)
      assert <<5, 0, 0, 4, _ipv6::binary-size(16), 443::16>> = binary
    end
  end

  describe "encode_connect_request_domain/2" do
    test "encodes domain CONNECT request" do
      binary = Socks5Codec.encode_connect_request_domain("example.com", 443)
      assert <<5, 1, 0, 3, 11, "example.com", 443::16>> == binary
    end
  end

  describe "fragmentation handling (round-trip)" do
    # This is the scenario that broke RemoteTunnel previously: protocol records
    # arriving split across multiple TCP reads.

    test "method reply + auth status + connect reply can be assembled from fragments" do
      # Simulate: byte-at-a-time feed to the parsers.
      full =
        Socks5Codec.encode_method_reply(2) <>
          Socks5Codec.encode_auth_reply(0) <>
          Socks5Codec.encode_reply(0, {10, 0, 0, 1}, 80)

      # Parse method reply with only 1 byte available
      assert {:need_more, _} = Socks5Codec.parse_method_reply(binary_part(full, 0, 1))

      # Parse with exact 2 bytes
      {:ok, 2, leftover1} = Socks5Codec.parse_method_reply(binary_part(full, 0, 2))
      assert leftover1 == <<>>

      # Parse auth reply from the next 2 bytes
      {:ok, 0, leftover2} = Socks5Codec.parse_auth_response(binary_part(full, 2, 2))
      assert leftover2 == <<>>

      # Parse final connect reply from remainder (10 bytes IPv4)
      {:ok, {0, "10.0.0.1", 80}, <<>>} =
        Socks5Codec.parse_reply(binary_part(full, 4, byte_size(full) - 4))
    end
  end
end
