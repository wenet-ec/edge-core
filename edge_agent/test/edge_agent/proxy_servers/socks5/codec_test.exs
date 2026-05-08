# edge_agent/test/edge_agent/proxy_servers/socks5/codec_test.exs
defmodule EdgeAgent.ProxyServers.Socks5.CodecTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.ProxyServers.Socks5.Codec

  # ---------------------------------------------------------------------------
  # parse_greeting/1 — RFC 1928 §3 client greeting:
  #   VER (1) | NMETHODS (1) | METHODS (NMETHODS bytes)
  # ---------------------------------------------------------------------------

  describe "parse_greeting/1" do
    test "decodes a complete greeting and returns the method list" do
      assert Codec.parse_greeting(<<5, 2, 0, 2>>) == {:ok, [0, 2], <<>>}
    end

    test "leaves trailing bytes in `rest`" do
      assert Codec.parse_greeting(<<5, 1, 2, "extra">>) == {:ok, [2], "extra"}
    end

    test "single-method greeting" do
      assert Codec.parse_greeting(<<5, 1, 0>>) == {:ok, [0], <<>>}
    end

    test "rejects non-SOCKS5 version" do
      assert Codec.parse_greeting(<<4, 1, 0>>) == {:error, {:unsupported_version, 4}}
    end

    test "needs at least 2 bytes (VER + NMETHODS) before deciding" do
      assert Codec.parse_greeting(<<>>) == {:need_more, 2}
      assert Codec.parse_greeting(<<5>>) == {:need_more, 2}
    end

    test "asks for more when methods are not yet present" do
      # VER=5, NMETHODS=3, only 1 method byte present → need 2 more.
      assert Codec.parse_greeting(<<5, 3, 0>>) == {:need_more, 2}
    end
  end

  # ---------------------------------------------------------------------------
  # parse_auth_request/1 — RFC 1929 username/password subnegotiation:
  #   VER=1 | ULEN | UNAME | PLEN | PASSWD
  # ---------------------------------------------------------------------------

  describe "parse_auth_request/1" do
    test "decodes a complete auth request" do
      packet = <<1, 5, "alice", 6, "secret"::binary>>
      assert Codec.parse_auth_request(packet) == {:ok, {"alice", "secret"}, <<>>}
    end

    test "leaves trailing bytes in `rest`" do
      packet = <<1, 1, "u", 1, "p", "tail"::binary>>
      assert Codec.parse_auth_request(packet) == {:ok, {"u", "p"}, "tail"}
    end

    test "rejects non-RFC1929 auth version" do
      assert Codec.parse_auth_request(<<2, 0>>) == {:error, {:unsupported_auth_version, 2}}
    end

    test "needs at least 2 bytes (VER + ULEN) before deciding" do
      assert Codec.parse_auth_request(<<>>) == {:need_more, 2}
      assert Codec.parse_auth_request(<<1>>) == {:need_more, 2}
    end

    test "asks for more when username + plen byte aren't yet present" do
      # VER=1, ULEN=4, no username bytes yet → need 5 more (4 for username + 1 PLEN).
      assert Codec.parse_auth_request(<<1, 4>>) == {:need_more, 5}
    end

    test "asks for more when password bytes haven't fully arrived" do
      # VER=1, ULEN=2, UNAME=ab, PLEN=4, but only 1 password byte → need 3 more.
      packet = <<1, 2, "ab", 4, "p">>
      assert Codec.parse_auth_request(packet) == {:need_more, 3}
    end
  end

  # ---------------------------------------------------------------------------
  # parse_connect_request/1 — RFC 1928 §4:
  #   VER (1) | CMD (1) | RSV=0 (1) | ATYP (1) | DST.ADDR | DST.PORT (2)
  # ---------------------------------------------------------------------------

  describe "parse_connect_request/1 — IPv4" do
    test "decodes a complete IPv4 CONNECT request" do
      packet = <<5, 1, 0, 1, 192, 168, 1, 100, 0x01, 0xBB>>
      assert Codec.parse_connect_request(packet) == {:ok, {1, "192.168.1.100", 443}, <<>>}
    end

    test "asks for more when address+port haven't fully arrived" do
      # VER + CMD + RSV + ATYP=IPv4, then need 6 bytes of addr+port; got 0.
      assert Codec.parse_connect_request(<<5, 1, 0, 1>>) == {:need_more, 6}
    end
  end

  describe "parse_connect_request/1 — IPv6" do
    test "decodes a complete IPv6 CONNECT request, lowercase zero-padded" do
      addr = <<0x2001::16, 0xDB8::16, 0::16, 0::16, 0::16, 0::16, 0::16, 1::16>>
      packet = <<5, 1, 0, 4>> <> addr <> <<0, 80>>

      assert Codec.parse_connect_request(packet) ==
               {:ok, {1, "2001:0db8:0000:0000:0000:0000:0000:0001", 80}, <<>>}
    end

    test "asks for more when 16-byte addr + port haven't arrived" do
      # ATYP=IPv6 → need 18 bytes (addr + port).
      assert Codec.parse_connect_request(<<5, 1, 0, 4>>) == {:need_more, 18}
    end
  end

  describe "parse_connect_request/1 — domain" do
    test "decodes a domain-name CONNECT request" do
      host = "example.com"
      packet = <<5, 1, 0, 3, byte_size(host)>> <> host <> <<0x01, 0xBB>>

      assert Codec.parse_connect_request(packet) ==
               {:ok, {1, "example.com", 443}, <<>>}
    end

    test "asks for more when host bytes haven't fully arrived" do
      # ATYP=domain, len=10, but only 4 host bytes + no port → need 8 more.
      packet = <<5, 1, 0, 3, 10, "exam"::binary>>
      assert Codec.parse_connect_request(packet) == {:need_more, 8}
    end

    test "asks for at least one byte (the length prefix) when domain is empty" do
      assert Codec.parse_connect_request(<<5, 1, 0, 3>>) == {:need_more, 1}
    end
  end

  describe "parse_connect_request/1 — errors" do
    test "rejects non-SOCKS5 version" do
      assert Codec.parse_connect_request(<<4, 1, 0, 1, 0, 0, 0, 0, 0, 80>>) ==
               {:error, {:unsupported_version, 4}}
    end

    test "rejects unknown address type" do
      # ATYP=2 isn't defined.
      packet = <<5, 1, 0, 2, 0, 0, 0, 0, 0, 80>>
      assert Codec.parse_connect_request(packet) == {:error, {:unsupported_address_type, 2}}
    end

    test "needs at least 4 header bytes before deciding" do
      assert Codec.parse_connect_request(<<>>) == {:need_more, 4}
      assert Codec.parse_connect_request(<<5, 1, 0>>) == {:need_more, 1}
    end
  end

  # ---------------------------------------------------------------------------
  # encode_reply/3 — server reply: VER | REP | RSV=0 | ATYP | BND.ADDR | BND.PORT
  # ---------------------------------------------------------------------------

  describe "encode_reply/3" do
    test "encodes a successful IPv4 reply" do
      assert Codec.encode_reply(0, {127, 0, 0, 1}, 8080) ==
               <<5, 0, 0, 1, 127, 0, 0, 1, 0x1F, 0x90>>
    end

    test "nil bound address renders as 0.0.0.0 with ATYP=IPv4" do
      # Documents: 'no bound address' uses the IPv4 wildcard, not a separate
      # ATYP. Clients see a normal IPv4 reply with addr 0.0.0.0.
      assert Codec.encode_reply(0, nil, 0) == <<5, 0, 0, 1, 0, 0, 0, 0, 0, 0>>
    end

    test "encodes an IPv6 reply" do
      addr = {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
      result = Codec.encode_reply(0, addr, 443)

      # Verify the structure piece by piece rather than hand-counting bytes:
      #   1B SOCKS5 version | 1B reply code | 1B RSV | 1B ATYP=IPv6 (4)
      #   16B address (8 segments × 2 bytes, big-endian)
      #   2B port (big-endian)
      assert <<5, 0, 0, 4, addr_bytes::binary-size(16), port::16>> = result
      assert port == 443
      assert byte_size(result) == 22

      # Each segment lands as 2 big-endian bytes.
      <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>> = addr_bytes
      assert {a, b, c, d, e, f, g, h} == {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
    end

    test "passes the reply code through verbatim" do
      # Common reply codes: 0=success, 1=general failure, 5=connection refused.
      for code <- [0, 1, 2, 3, 4, 5, 6, 7, 8] do
        <<_ver, byte, _rsv, _atyp, _addr::binary-size(4), _port::16>> =
          Codec.encode_reply(code, {0, 0, 0, 0}, 0)

        assert byte == code
      end
    end
  end

  # ---------------------------------------------------------------------------
  # encode_method_reply/1, encode_auth_reply/1
  # ---------------------------------------------------------------------------

  describe "encode_method_reply/1" do
    test "wraps the method byte with the SOCKS5 version prefix" do
      # 0x00 = no auth, 0x02 = userpass, 0xFF = no acceptable methods.
      assert Codec.encode_method_reply(0x00) == <<5, 0>>
      assert Codec.encode_method_reply(0x02) == <<5, 2>>
      assert Codec.encode_method_reply(0xFF) == <<5, 0xFF>>
    end
  end

  describe "encode_auth_reply/1" do
    test "wraps the status byte with the RFC 1929 version prefix" do
      # 0 = success, anything else = failure.
      assert Codec.encode_auth_reply(0) == <<1, 0>>
      assert Codec.encode_auth_reply(1) == <<1, 1>>
    end
  end
end
