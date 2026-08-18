# edge_admin/test/edge_admin_proxy/http/request_test.exs
defmodule EdgeAdminProxy.Http.RequestTest do
  use ExUnit.Case, async: true

  alias EdgeAdminProxy.Http.Request

  test "requires absolute-form URIs except for CONNECT" do
    assert Request.validate_proxy_form("CONNECT", "example.com:443") == :ok
    assert Request.validate_proxy_form("GET", "http://example.com/path") == :ok
    assert Request.validate_proxy_form("GET", "/path") == {:error, :origin_form_uri}
  end

  test "normalises host, strips hop-by-hop headers, and builds requests" do
    headers = [{"Host", "old"}, {"Connection", "keep-alive"}, {"X-Test", "1"}]

    result =
      headers
      |> Request.reconcile_host_header("example.com", 8080)
      |> Request.filter_hop_by_hop_headers()
      |> Request.add_via_header("HTTP/1.1", "edge-admin")

    assert {"host", "example.com:8080"} in result
    refute {"connection", "keep-alive"} in result
    assert {"via", "1.1 edge-admin"} in result
    assert Request.build_http_request("GET", "/", "HTTP/1.1", result) =~ "GET / HTTP/1.1"
  end

  test "parses HTTP and CONNECT targets" do
    assert Request.parse_http_uri("https://example.com/path") == {:ok, "example.com", 443, "/path"}
    assert Request.parse_host_port("example.com:443") == {:ok, "example.com", 443}
  end
end
