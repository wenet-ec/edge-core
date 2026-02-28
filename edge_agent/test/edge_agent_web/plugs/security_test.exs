# edge_agent/test/edge_agent_web/plugs/security_test.exs
defmodule EdgeAgentWeb.Plugs.SecurityTest do
  use EdgeAgentWeb.ConnCase

  alias EdgeAgentWeb.Plugs.Security

  defp call(conn), do: Security.call(conn, Security.init([]))

  defp csp(conn) do
    conn
    |> get_resp_header("content-security-policy")
    |> hd()
  end

  defp with_unsafe_scripts(value, fun) do
    old = Application.get_env(:edge_agent, Security)
    Application.put_env(:edge_agent, Security, allow_unsafe_scripts: value)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:edge_agent, Security)
      else
        Application.put_env(:edge_agent, Security, old)
      end
    end
  end

  describe "call/2 — CSP header is always set" do
    test "sets content-security-policy header", %{conn: conn} do
      conn = call(conn)
      headers = get_resp_header(conn, "content-security-policy")
      assert length(headers) == 1
    end

    test "conn is not halted", %{conn: conn} do
      conn = call(conn)
      refute conn.halted
    end
  end

  describe "call/2 — CSP directive values" do
    test "default-src is 'none'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "default-src 'none'"
    end

    test "form-action is 'self'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "form-action 'self'"
    end

    test "media-src is 'self'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "media-src 'self'"
    end

    test "font-src is 'self'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "font-src 'self'"
    end

    test "connect-src is 'self'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "connect-src 'self'"
    end

    test "style-src allows 'self' and 'unsafe-inline'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "style-src 'self' 'unsafe-inline'"
    end

    test "frame-src is 'self'", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "frame-src 'self'"
    end

    test "img-src allows 'self' and data:", %{conn: conn} do
      conn = call(conn)
      assert csp(conn) =~ "img-src 'self' data:"
    end

    test "all 9 directives are present", %{conn: conn} do
      conn = call(conn)
      policy = csp(conn)

      for directive <- ~w(default-src form-action media-src img-src script-src font-src connect-src style-src frame-src) do
        assert policy =~ directive, "missing directive: #{directive}"
      end
    end
  end

  describe "call/2 — script-src without allow_unsafe_scripts" do
    test "script-src is only 'self' by default", %{conn: conn} do
      Application.delete_env(:edge_agent, Security)
      conn = call(conn)
      policy = csp(conn)
      # script-src must be exactly "'self'" with no unsafe additions
      assert policy =~ "script-src 'self'"
      refute policy =~ "'unsafe-eval'"
      # Note: 'unsafe-inline' appears in style-src (always), so we check script-src specifically
      assert policy =~ "script-src 'self';"
    end
  end

  describe "call/2 — script-src with allow_unsafe_scripts: true" do
    test "script-src includes 'unsafe-eval' and 'unsafe-inline'", %{conn: conn} do
      with_unsafe_scripts(true, fn ->
        conn = call(conn)
        policy = csp(conn)
        assert policy =~ "'unsafe-eval'"
        assert policy =~ "'unsafe-inline'"
      end)
    end

    test "script-src still includes 'self' when unsafe scripts enabled", %{conn: conn} do
      with_unsafe_scripts(true, fn ->
        conn = call(conn)
        assert csp(conn) =~ "script-src 'self'"
      end)
    end
  end

  describe "call/2 — allow_unsafe_scripts: false" do
    test "script-src is only 'self' when explicitly false", %{conn: conn} do
      with_unsafe_scripts(false, fn ->
        conn = call(conn)
        policy = csp(conn)
        assert policy =~ "script-src 'self'"
        refute policy =~ "'unsafe-eval'"
      end)
    end
  end
end
