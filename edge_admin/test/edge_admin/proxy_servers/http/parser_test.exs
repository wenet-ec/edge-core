# edge_admin/test/edge_admin/proxy_servers/http/parser_test.exs
defmodule EdgeAdmin.ProxyServers.Http.ParserTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ProxyServers.Http.Parser, as: HttpParser

  # Fake transport — reads bytes from an Agent holding a byte queue.
  # No sockets involved; tests the parser's logic purely.
  defmodule FakeTransport do
    @moduledoc false

    def recv(agent, _length, _timeout) do
      case Agent.get_and_update(agent, fn
             [chunk | rest] -> {chunk, rest}
             [] -> {:empty, []}
           end) do
        :empty -> {:error, :timeout}
        chunk -> {:ok, chunk}
      end
    end
  end

  defp new_feed(chunks) when is_list(chunks) do
    {:ok, agent} = Agent.start_link(fn -> chunks end)
    agent
  end

  defp new_feed(bytes) when is_binary(bytes), do: new_feed([bytes])

  describe "read_request/3" do
    test "parses a simple absolute-URI request" do
      feed =
        new_feed("GET http://example.com/path HTTP/1.1\r\nHost: example.com\r\nAccept: */*\r\n\r\n")

      assert {:ok, parsed, _rest} = HttpParser.read_request(feed, FakeTransport, 1_000)
      assert parsed.method == "GET"
      assert parsed.uri =~ "example.com"
      assert parsed.version == "HTTP/1.1"
      assert {"host", "example.com"} in parsed.headers
    end

    test "parses CONNECT request (authority form)" do
      feed = new_feed("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")

      assert {:ok, parsed, _} = HttpParser.read_request(feed, FakeTransport, 1_000)
      assert parsed.method == "CONNECT"
      # URI for CONNECT comes through as authority-form; decode_packet represents
      # it various ways depending on OTP version — we just assert it contains the host.
      assert parsed.uri =~ "example.com"
    end

    test "handles fragmented delivery of headers" do
      feed =
        new_feed([
          "GET http://ex.com/ HTTP/1.1\r\nHost: ",
          "ex.com\r\n",
          "Connection: close\r\n\r\n"
        ])

      assert {:ok, parsed, _} = HttpParser.read_request(feed, FakeTransport, 2_000)
      assert parsed.method == "GET"
      assert {"connection", "close"} in parsed.headers
    end

    test "lowercases header names" do
      feed =
        new_feed("GET http://a/ HTTP/1.1\r\nProxy-Authorization: Basic xxx\r\nX-Custom-Thing: yes\r\n\r\n")

      assert {:ok, parsed, _} = HttpParser.read_request(feed, FakeTransport, 1_000)
      names = Enum.map(parsed.headers, fn {k, _} -> k end)
      assert "proxy-authorization" in names
      assert "x-custom-thing" in names
    end
  end
end
