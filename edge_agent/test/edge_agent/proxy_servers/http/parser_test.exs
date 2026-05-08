# edge_agent/test/edge_agent/proxy_servers/http/parser_test.exs
defmodule EdgeAgent.ProxyServers.Http.ParserTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.ProxyServers.Http.Parser

  # ---------------------------------------------------------------------------
  # to_method/1 — atom (well-known) or binary (custom) → uppercase string
  # ---------------------------------------------------------------------------

  describe "to_method/1" do
    test "uppercases atom methods returned by :erlang.decode_packet" do
      assert Parser.to_method(:GET) == "GET"
      assert Parser.to_method(:POST) == "POST"
      assert Parser.to_method(:CONNECT) == "CONNECT"
      assert Parser.to_method(:HEAD) == "HEAD"
    end

    test "uppercases binary methods (custom verbs)" do
      assert Parser.to_method("PROPFIND") == "PROPFIND"
      assert Parser.to_method("propfind") == "PROPFIND"
      assert Parser.to_method("MkCol") == "MKCOL"
    end
  end

  # ---------------------------------------------------------------------------
  # to_uri/1 — five different shapes from :erlang.decode_packet
  # ---------------------------------------------------------------------------

  describe "to_uri/1" do
    test "{:abs_path, path} → path string" do
      assert Parser.to_uri({:abs_path, "/foo/bar"}) == "/foo/bar"
    end

    test "{:absoluteURI, ...} → scheme://host[:port]/path" do
      assert Parser.to_uri({:absoluteURI, :http, "example.com", :undefined, "/path"}) ==
               "http://example.com/path"

      assert Parser.to_uri({:absoluteURI, :https, "example.com", 8443, "/secure"}) ==
               "https://example.com:8443/secure"
    end

    test "{:scheme, scheme, rest} → scheme:rest (host:port form for CONNECT)" do
      assert Parser.to_uri({:scheme, "example.com", "443"}) == "example.com:443"
    end

    test "charlist '*' (asterisk-form, OPTIONS *) → \"*\"" do
      assert Parser.to_uri(~c"*") == "*"
    end

    test "binary URI passes through unchanged" do
      assert Parser.to_uri("/already-a-string") == "/already-a-string"
    end

    test "non-asterisk charlist is converted to a string" do
      assert Parser.to_uri(~c"/some/path") == "/some/path"
    end
  end

  # ---------------------------------------------------------------------------
  # stringify_uri/1 — the three tuple forms
  # ---------------------------------------------------------------------------

  describe "stringify_uri/1" do
    test "absoluteURI without port omits the colon" do
      assert Parser.stringify_uri({:absoluteURI, :http, "example.com", :undefined, "/x"}) ==
               "http://example.com/x"
    end

    test "absoluteURI with port renders host:port" do
      assert Parser.stringify_uri({:absoluteURI, :https, "example.com", 8080, "/x"}) ==
               "https://example.com:8080/x"
    end

    test "scheme tuple renders as scheme:rest" do
      assert Parser.stringify_uri({:scheme, "example.com", "443"}) == "example.com:443"
    end
  end

  # ---------------------------------------------------------------------------
  # to_header_name/1 — atom or binary → lowercase string
  # ---------------------------------------------------------------------------

  describe "to_header_name/1" do
    test "lowercases atom header names returned by :erlang.decode_packet" do
      assert Parser.to_header_name(:Host) == "host"
      assert Parser.to_header_name(:"Content-Type") == "content-type"
      assert Parser.to_header_name(:"User-Agent") == "user-agent"
    end

    test "lowercases binary header names (custom headers)" do
      assert Parser.to_header_name("X-Custom-Header") == "x-custom-header"
      assert Parser.to_header_name("PROXY-AUTHORIZATION") == "proxy-authorization"
      assert Parser.to_header_name("already-lowercase") == "already-lowercase"
    end
  end
end
