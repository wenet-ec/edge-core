# edge_admin/test/edge_admin/proxy_servers/http/handler_test.exs
defmodule EdgeAdmin.ProxyServers.Http.HandlerTest do
  # async: false because tests touch :via_pseudonym application env. The
  # Handler reads it lazily on every call, so racing test writes would cross
  # talk between cases.
  use ExUnit.Case, async: false

  alias EdgeAdmin.ProxyServers.Http.Handler

  # ---------------------------------------------------------------------------
  # validate_proxy_form/2
  # ---------------------------------------------------------------------------

  describe "validate_proxy_form/2" do
    test "CONNECT bypasses URI shape (uri carries host:port, not a URI)" do
      assert Handler.validate_proxy_form("CONNECT", "example.com:443") == :ok
    end

    test "non-CONNECT requires absolute-form URI (scheme + host)" do
      assert Handler.validate_proxy_form("GET", "http://example.com/path") == :ok
      assert Handler.validate_proxy_form("POST", "https://example.com/") == :ok
    end

    test "non-CONNECT rejects origin-form URI (no scheme/host)" do
      assert Handler.validate_proxy_form("GET", "/path") == {:error, :origin_form_uri}
      assert Handler.validate_proxy_form("GET", "") == {:error, :origin_form_uri}
    end
  end

  # ---------------------------------------------------------------------------
  # check_loop/1 — uses via_pseudonym/0 from app env
  # ---------------------------------------------------------------------------

  describe "check_loop/1" do
    setup do
      previous = Elixir.Application.get_env(:edge_admin, :via_pseudonym)
      Application.put_env(:edge_admin, :via_pseudonym, "edge-admin")

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:edge_admin, :via_pseudonym)
        else
          Application.put_env(:edge_admin, :via_pseudonym, previous)
        end
      end)

      :ok
    end

    test "no Via header → :ok" do
      assert Handler.check_loop([{"host", "example.com"}]) == :ok
    end

    test "Via without our pseudonym → :ok" do
      assert Handler.check_loop([{"via", "1.1 some-other-proxy"}]) == :ok
    end

    test "Via containing our pseudonym → loop_detected" do
      assert Handler.check_loop([{"via", "1.1 edge-admin"}]) == {:error, :loop_detected}
    end

    test "loop detection survives header name case differences" do
      assert Handler.check_loop([{"Via", "1.1 edge-admin"}]) == {:error, :loop_detected}
    end

    test "loop detection works mid-chain" do
      assert Handler.check_loop([{"via", "1.0 first, 1.1 edge-admin, 1.1 last"}]) ==
               {:error, :loop_detected}
    end
  end

  # ---------------------------------------------------------------------------
  # get_header/2
  # ---------------------------------------------------------------------------

  describe "get_header/2" do
    test "case-insensitive on header name" do
      headers = [{"Content-Type", "application/json"}]
      assert Handler.get_header(headers, "content-type") == "application/json"
      assert Handler.get_header(headers, "CONTENT-TYPE") == "application/json"
    end

    test "returns first match when duplicates exist" do
      headers = [{"x-custom", "first"}, {"X-Custom", "second"}]
      assert Handler.get_header(headers, "x-custom") == "first"
    end

    test "returns nil when missing" do
      assert Handler.get_header([], "host") == nil
      assert Handler.get_header([{"host", "x"}], "via") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # reconcile_host_header/3
  # ---------------------------------------------------------------------------

  describe "reconcile_host_header/3" do
    test "elides port for HTTP default 80" do
      [{"host", host_value} | _] = Handler.reconcile_host_header([], "example.com", 80)
      assert host_value == "example.com"
    end

    test "elides port for HTTPS default 443" do
      [{"host", host_value} | _] = Handler.reconcile_host_header([], "example.com", 443)
      assert host_value == "example.com"
    end

    test "appends port for non-default ports" do
      [{"host", host_value} | _] = Handler.reconcile_host_header([], "example.com", 8080)
      assert host_value == "example.com:8080"
    end

    test "drops any prior Host headers regardless of case" do
      headers = [{"Host", "old.example.com"}, {"host", "older.example.com"}, {"x-other", "keep"}]
      result = Handler.reconcile_host_header(headers, "new.example.com", 80)

      # The new Host is first; only the kept header survives, no Host duplicates.
      assert [{"host", "new.example.com"}, {"x-other", "keep"}] = result
    end
  end

  # ---------------------------------------------------------------------------
  # filter_hop_by_hop_headers/1
  # ---------------------------------------------------------------------------

  describe "filter_hop_by_hop_headers/1" do
    test "strips RFC 7230 hop-by-hop names regardless of case" do
      headers = [
        {"Connection", "keep-alive"},
        {"Keep-Alive", "timeout=5"},
        {"Proxy-Authenticate", "Basic"},
        {"Proxy-Authorization", "Basic abcd"},
        {"Proxy-Connection", "keep-alive"},
        {"TE", "trailers"},
        {"Trailer", "Expires"},
        {"Transfer-Encoding", "chunked"},
        {"Upgrade", "websocket"},
        {"Content-Type", "text/plain"}
      ]

      assert Handler.filter_hop_by_hop_headers(headers) == [{"Content-Type", "text/plain"}]
    end

    test "expands Connection-listed names into the drop set" do
      headers = [
        {"connection", "x-foo, x-bar"},
        {"x-foo", "1"},
        {"x-bar", "2"},
        {"x-keep", "3"}
      ]

      assert Handler.filter_hop_by_hop_headers(headers) == [{"x-keep", "3"}]
    end

    test "preserves Upgrade chain when Connection lists 'upgrade'" do
      headers = [
        {"connection", "upgrade"},
        {"upgrade", "websocket"},
        {"sec-websocket-key", "abc"}
      ]

      result = Handler.filter_hop_by_hop_headers(headers)

      # connection + upgrade get dropped by the hop-by-hop pass, then preserve_upgrade
      # reinjects them with normalised values. sec-websocket-key passes through.
      assert {"connection", "Upgrade"} in result
      assert {"upgrade", "websocket"} in result
      assert {"sec-websocket-key", "abc"} in result
    end

    test "absence of Connection header is fine (to_string(nil) == \"\")" do
      assert Handler.filter_hop_by_hop_headers([{"x-keep", "1"}]) == [{"x-keep", "1"}]
    end

    test "Connection list is case- and whitespace-tolerant" do
      headers = [
        {"connection", "  X-Foo , X-Bar  "},
        {"x-foo", "1"},
        {"X-BAR", "2"}
      ]

      assert Handler.filter_hop_by_hop_headers(headers) == []
    end
  end

  # ---------------------------------------------------------------------------
  # add_via_header/2
  # ---------------------------------------------------------------------------

  describe "add_via_header/2" do
    setup do
      previous = Elixir.Application.get_env(:edge_admin, :via_pseudonym)
      Application.put_env(:edge_admin, :via_pseudonym, "edge-admin")

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:edge_admin, :via_pseudonym)
        else
          Application.put_env(:edge_admin, :via_pseudonym, previous)
        end
      end)

      :ok
    end

    test "creates a Via header when none exists" do
      result = Handler.add_via_header([], "HTTP/1.1")
      assert [{"via", "1.1 edge-admin"}] = result
    end

    test "appends to an existing Via with comma-space" do
      result = Handler.add_via_header([{"via", "1.0 upstream"}], "HTTP/1.1")
      assert [{"via", "1.0 upstream, 1.1 edge-admin"}] = result
    end

    test "drops the old Via entry (regardless of case) before prepending the new one" do
      headers = [{"Via", "1.0 upstream"}, {"x-other", "keep"}]
      result = Handler.add_via_header(headers, "HTTP/1.1")

      assert [{"via", "1.0 upstream, 1.1 edge-admin"}, {"x-other", "keep"}] == result
    end
  end

  # ---------------------------------------------------------------------------
  # parse_http_version/1
  # ---------------------------------------------------------------------------

  describe "parse_http_version/1" do
    test "strips HTTP/ prefix for known versions" do
      assert Handler.parse_http_version("HTTP/1.0") == "1.0"
      assert Handler.parse_http_version("HTTP/1.1") == "1.1"
    end

    test "strips HTTP/ prefix generically (unknown versions)" do
      assert Handler.parse_http_version("HTTP/2.0") == "2.0"
      assert Handler.parse_http_version("HTTP/3") == "3"
    end

    test "falls back to '1.1' for unrecognised input" do
      assert Handler.parse_http_version("garbage") == "1.1"
      assert Handler.parse_http_version("") == "1.1"
    end
  end

  # ---------------------------------------------------------------------------
  # validate_external_destination/2 + predicates
  # ---------------------------------------------------------------------------

  describe "validate_external_destination/2" do
    test "blocks loopback hosts" do
      assert Handler.validate_external_destination("localhost", 80) == {:error, :localhost_blocked}
      assert Handler.validate_external_destination("127.0.0.1", 80) == {:error, :localhost_blocked}
      assert Handler.validate_external_destination("0.0.0.0", 80) == {:error, :localhost_blocked}
      assert Handler.validate_external_destination("::1", 80) == {:error, :localhost_blocked}
      assert Handler.validate_external_destination("127.5.5.5", 80) == {:error, :localhost_blocked}
    end

    test "blocks link-local IPv4" do
      assert Handler.validate_external_destination("169.254.1.2", 80) ==
               {:error, :link_local_blocked}
    end

    test "blocks cloud metadata endpoints (loopback check fires first when both apply)" do
      # 169.254.169.254 matches both link_local? and metadata_service?; loopback? is false.
      # Order in validate_external_destination: loopback → link_local → metadata.
      assert Handler.validate_external_destination("metadata.google.internal", 80) ==
               {:error, :metadata_service_blocked}

      assert Handler.validate_external_destination("metadata.azure.com", 80) ==
               {:error, :metadata_service_blocked}

      # 169.254.169.254 matches link_local? first, so it returns :link_local_blocked
      # rather than :metadata_service_blocked. Documenting actual precedence.
      assert Handler.validate_external_destination("169.254.169.254", 80) ==
               {:error, :link_local_blocked}
    end

    test "blocks orchestration ports (Docker, k8s, etcd)" do
      for port <- [2375, 2376, 2377, 6443, 10_250, 10_255, 2379, 2380] do
        assert Handler.validate_external_destination("example.com", port) ==
                 {:error, :blocked_port},
               "expected port #{port} to be blocked"
      end
    end

    test "passes :ok for safe public destinations" do
      assert Handler.validate_external_destination("example.com", 443) == :ok
      assert Handler.validate_external_destination("8.8.8.8", 53) == :ok
    end
  end

  describe "loopback?/1" do
    test "matches host literals" do
      assert Handler.loopback?("localhost")
      assert Handler.loopback?("LOCALHOST")
      assert Handler.loopback?("127.0.0.1")
      assert Handler.loopback?("0.0.0.0")
      assert Handler.loopback?("::1")
    end

    test "matches any 127.x" do
      assert Handler.loopback?("127.5.5.5")
      assert Handler.loopback?("127.255.255.255")
    end

    test "rejects everything else" do
      refute Handler.loopback?("example.com")
      refute Handler.loopback?("8.8.8.8")
      refute Handler.loopback?("128.0.0.1")
    end
  end

  describe "link_local?/1" do
    test "matches 169.254.x.x" do
      assert Handler.link_local?("169.254.0.1")
      assert Handler.link_local?("169.254.169.254")
    end

    test "rejects neighbours and non-IPv4" do
      refute Handler.link_local?("169.253.0.1")
      refute Handler.link_local?("169.255.0.1")
      refute Handler.link_local?("example.com")
    end
  end

  describe "metadata_service?/1" do
    test "matches the four documented endpoints (case-insensitive)" do
      assert Handler.metadata_service?("metadata.google.internal")
      assert Handler.metadata_service?("Metadata.Google.Internal")
      assert Handler.metadata_service?("metadata.azure.com")
      assert Handler.metadata_service?("169.254.169.254")
      assert Handler.metadata_service?("100.100.100.200")
    end

    test "rejects look-alikes" do
      refute Handler.metadata_service?("metadata.example.com")
      refute Handler.metadata_service?("not-metadata.google.internal")
    end
  end

  describe "blocked_ports/0" do
    test "is the documented set" do
      assert Handler.blocked_ports() == [2375, 2376, 2377, 6443, 10_250, 10_255, 2379, 2380]
    end
  end

  describe "vpn_target?/1" do
    setup do
      previous = Application.get_env(:edge_admin, :netmaker_default_domain)
      Application.put_env(:edge_admin, :netmaker_default_domain, "nm.internal")

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:edge_admin, :netmaker_default_domain)
        else
          Application.put_env(:edge_admin, :netmaker_default_domain, previous)
        end
      end)

      :ok
    end

    test "returns true for VPN hostnames under the configured domain" do
      assert Handler.vpn_target?("node-123.cluster-prod.nm.internal")
      assert Handler.vpn_target?("api.cluster-prod.nm.internal")
    end

    test "returns false for non-VPN hosts including RFC1918 literals" do
      refute Handler.vpn_target?("example.com")
      refute Handler.vpn_target?("192.168.1.127")
      refute Handler.vpn_target?("10.0.0.5")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_ipv4/1
  # ---------------------------------------------------------------------------

  describe "parse_ipv4/1" do
    test "parses dotted-quad" do
      assert Handler.parse_ipv4("169.254.0.1") == {169, 254, 0, 1}
      assert Handler.parse_ipv4("0.0.0.0") == {0, 0, 0, 0}
    end

    test "returns nil for non-IPv4 shapes" do
      assert Handler.parse_ipv4("example.com") == nil
      assert Handler.parse_ipv4("1.2.3") == nil
      assert Handler.parse_ipv4("1.2.3.4.5") == nil
    end

    test "returns nil when any segment isn't a clean integer" do
      assert Handler.parse_ipv4("1.2.3.abc") == nil
      assert Handler.parse_ipv4("1.2.3.4a") == nil
      assert Handler.parse_ipv4("..1.2") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # build_http_request/4
  # ---------------------------------------------------------------------------

  describe "build_http_request/4" do
    test "produces request line + headers + blank-line terminator" do
      result =
        Handler.build_http_request("GET", "/path", "HTTP/1.1", [
          {"host", "example.com"},
          {"x-custom", "value"}
        ])

      assert result ==
               "GET /path HTTP/1.1\r\n" <>
                 "host: example.com\r\n" <>
                 "x-custom: value\r\n" <>
                 "\r\n"
    end

    test "preserves header order" do
      result = Handler.build_http_request("POST", "/", "HTTP/1.1", [{"a", "1"}, {"b", "2"}])
      # Ordering matters for some downstream consumers; lock it in.
      assert result =~ ~r/a: 1\r\nb: 2\r\n/
    end

    test "no headers → request line + blank line" do
      assert Handler.build_http_request("GET", "/", "HTTP/1.1", []) == "GET / HTTP/1.1\r\n\r\n"
    end
  end

  # ---------------------------------------------------------------------------
  # parse_http_uri/1
  # ---------------------------------------------------------------------------

  describe "parse_http_uri/1" do
    test "http with explicit port and path" do
      assert Handler.parse_http_uri("http://example.com:8080/path") ==
               {:ok, "example.com", 8080, "/path"}
    end

    test "http defaults port to 80 and path to '/' when missing" do
      assert Handler.parse_http_uri("http://example.com") == {:ok, "example.com", 80, "/"}
    end

    test "https defaults port to 443" do
      assert Handler.parse_http_uri("https://example.com/x") == {:ok, "example.com", 443, "/x"}
    end

    test "rejects non-http(s) schemes" do
      assert Handler.parse_http_uri("ftp://example.com/") == {:error, :invalid_uri}
      assert Handler.parse_http_uri("ws://example.com/") == {:error, :invalid_uri}
    end

    test "rejects malformed input (no host)" do
      assert Handler.parse_http_uri("/path") == {:error, :invalid_uri}
      assert Handler.parse_http_uri("not a uri") == {:error, :invalid_uri}
    end
  end

  # ---------------------------------------------------------------------------
  # parse_host_port/1
  # ---------------------------------------------------------------------------

  describe "parse_host_port/1" do
    test "splits host:port" do
      assert Handler.parse_host_port("example.com:443") == {:ok, "example.com", 443}
      assert Handler.parse_host_port("10.0.0.1:8080") == {:ok, "10.0.0.1", 8080}
    end

    test "rejects missing colon" do
      assert Handler.parse_host_port("example.com") == {:error, :invalid_format}
    end

    test "rejects non-integer port" do
      assert Handler.parse_host_port("example.com:abc") == {:error, :invalid_port}
    end

    test "Integer.parse is forgiving — partial numeric ports succeed" do
      # Documents actual behaviour: Integer.parse("443x") returns {443, "x"},
      # so this passes through with the parsed prefix. Not a bug worth fixing
      # at this layer (defence-in-depth catches it elsewhere), but lock it in
      # so a behaviour change is visible.
      assert Handler.parse_host_port("example.com:443x") == {:ok, "example.com", 443}
    end
  end

  # ---------------------------------------------------------------------------
  # via_pseudonym/0
  # ---------------------------------------------------------------------------

  describe "via_pseudonym/0" do
    test "defaults to 'edge-admin' when env unset" do
      previous = Elixir.Application.get_env(:edge_admin, :via_pseudonym)
      Application.delete_env(:edge_admin, :via_pseudonym)

      try do
        assert Handler.via_pseudonym() == "edge-admin"
      after
        if previous, do: Application.put_env(:edge_admin, :via_pseudonym, previous)
      end
    end

    test "uses configured value when set" do
      previous = Elixir.Application.get_env(:edge_admin, :via_pseudonym)
      Application.put_env(:edge_admin, :via_pseudonym, "custom-proxy")

      try do
        assert Handler.via_pseudonym() == "custom-proxy"
      after
        if is_nil(previous) do
          Application.delete_env(:edge_admin, :via_pseudonym)
        else
          Application.put_env(:edge_admin, :via_pseudonym, previous)
        end
      end
    end
  end
end
