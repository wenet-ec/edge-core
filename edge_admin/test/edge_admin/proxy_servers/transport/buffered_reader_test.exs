# edge_admin/test/edge_admin/proxy_servers/transport/buffered_reader_test.exs
defmodule EdgeAdmin.ProxyServers.Transport.BufferedReaderTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ProxyServers.Transport.BufferedReader

  describe "read_active/3" do
    test "accumulates fragmented TCP deliveries until the parser commits" do
      # The bug this module exists to prevent: a parser expecting a 4-byte
      # frame won't get 4 bytes in one delivery just because the sender wrote
      # 4 bytes — TCP can split that into any number of {:tcp, _, _} messages.
      # The reader has to glue fragments together until the parser is happy.

      # make_ref/0 is a unique term that the receive `^socket` pin can match.
      # In production this is a port; ref works for the unit test.
      socket = make_ref()

      # Parser: commit when the buffer reaches 4 bytes; ask for more otherwise.
      parser = fn
        <<value::binary-size(4), rest::binary>> -> {:ok, value, rest}
        _ -> {:need_more, 4}
      end

      # Three fragments that combine to "ABCDE" — the parser should commit
      # once "ABCD" is in the buffer, leaving "E" as the leftover.
      send(self(), {:tcp, socket, "AB"})
      send(self(), {:tcp, socket, "C"})
      send(self(), {:tcp, socket, "DE"})

      assert {:ok, "ABCD", "E"} = BufferedReader.read_active(socket, parser, 1_000)
    end
  end
end
