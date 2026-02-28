# edge_admin/test/edge_admin_web/plugs/security_test.exs
defmodule EdgeAdminWeb.Plugs.SecurityTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias EdgeAdminWeb.Plugs.Security

  @opts Security.init([])

  setup do
    on_exit(fn ->
      Application.delete_env(:edge_admin, Security)
    end)
  end

  defp call(path), do: :get |> conn(path) |> Security.call(@opts)

  defp csp(conn) do
    conn
    |> Plug.Conn.get_resp_header("content-security-policy")
    |> hd()
  end

  describe "regular routes" do
    test "sets content-security-policy header" do
      conn = call("/api/v1/nodes")
      assert csp(conn) =~ "default-src"
    end

    test "default-src is 'none'" do
      conn = call("/api/v1/nodes")
      assert csp(conn) =~ "default-src 'none'"
    end

    test "script-src is 'self' only when allow_unsafe_scripts not set" do
      Application.delete_env(:edge_admin, Security)
      conn = call("/api/v1/nodes")
      policy = csp(conn)
      assert policy =~ "script-src 'self'"
      refute policy =~ "'unsafe-eval'"
    end

    test "script-src includes unsafe directives when allow_unsafe_scripts is true" do
      Application.put_env(:edge_admin, Security, allow_unsafe_scripts: true)
      conn = call("/api/v1/nodes")
      policy = csp(conn)
      assert policy =~ "'unsafe-eval'"
      assert policy =~ "'unsafe-inline'"
    end

    test "does not include CDN sources in style-src" do
      conn = call("/api/v1/nodes")
      policy = csp(conn)
      refute policy =~ "cdnjs.cloudflare.com"
    end

    test "includes all required directive keys" do
      conn = call("/api/v1/nodes")
      policy = csp(conn)
      assert policy =~ "default-src"
      assert policy =~ "form-action"
      assert policy =~ "media-src"
      assert policy =~ "img-src"
      assert policy =~ "script-src"
      assert policy =~ "font-src"
      assert policy =~ "connect-src"
      assert policy =~ "style-src"
      assert policy =~ "frame-src"
    end

    test "does not halt the connection" do
      conn = call("/api/v1/nodes")
      refute conn.halted
    end
  end

  describe "docs routes — /swaggerui" do
    test "sets content-security-policy header" do
      conn = call("/swaggerui")
      assert csp(conn) =~ "default-src"
    end

    test "includes CDN sources for scripts" do
      conn = call("/swaggerui")
      policy = csp(conn)
      assert policy =~ "cdnjs.cloudflare.com"
    end

    test "script-src always includes unsafe-eval for docs" do
      conn = call("/swaggerui")
      policy = csp(conn)
      assert policy =~ "'unsafe-eval'"
      assert policy =~ "cdn.jsdelivr.net"
    end

    test "style-src includes Google Fonts" do
      conn = call("/swaggerui")
      policy = csp(conn)
      assert policy =~ "fonts.googleapis.com"
    end

    test "font-src includes Google Fonts static" do
      conn = call("/swaggerui")
      policy = csp(conn)
      assert policy =~ "fonts.gstatic.com"
    end

    test "img-src includes validator.swagger.io" do
      conn = call("/swaggerui")
      policy = csp(conn)
      assert policy =~ "validator.swagger.io"
    end

    test "does not halt the connection" do
      conn = call("/swaggerui")
      refute conn.halted
    end
  end

  describe "docs routes — /redoc" do
    test "uses docs CSP (includes CDN sources)" do
      conn = call("/redoc")
      policy = csp(conn)
      assert policy =~ "cdnjs.cloudflare.com"
    end

    test "script-src includes unsafe-eval" do
      conn = call("/redoc")
      assert csp(conn) =~ "'unsafe-eval'"
    end

    test "does not halt the connection" do
      conn = call("/redoc")
      refute conn.halted
    end
  end

  describe "regular vs docs CSP differ" do
    test "docs has more permissive script-src than regular" do
      regular_policy = "/api/v1/nodes" |> call() |> csp()
      docs_policy = "/swaggerui" |> call() |> csp()
      refute regular_policy == docs_policy
    end

    test "regular route does not include CDN sources that docs do" do
      regular_policy = "/api/v1/nodes" |> call() |> csp()
      refute regular_policy =~ "cdn.jsdelivr.net"
    end
  end
end
