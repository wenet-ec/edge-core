# edge_admin/test/edge_admin_web/plugs/mcp_auth_test.exs
defmodule EdgeAdminWeb.Plugs.McpAuthTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias EdgeAdminWeb.Plugs.McpAuth

  @opts McpAuth.init([])

  setup do
    Application.put_env(:edge_admin, :auth_enabled, true)
    Application.delete_env(:edge_admin, :master_key)
    Application.delete_env(:edge_admin, :mcp_key)

    on_exit(fn ->
      Application.put_env(:edge_admin, :auth_enabled, true)
      Application.delete_env(:edge_admin, :master_key)
      Application.delete_env(:edge_admin, :mcp_key)
    end)
  end

  defp build_conn(auth_header \\ nil) do
    conn = conn(:get, "/")

    if auth_header do
      put_req_header(conn, "authorization", auth_header)
    else
      conn
    end
  end

  describe "auth disabled" do
    test "passes through regardless of header" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      conn = McpAuth.call(build_conn(), @opts)
      refute conn.halted
    end

    test "passes through with wrong key" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      Application.put_env(:edge_admin, :mcp_key, "real-mcp-key")
      conn = "Bearer wrong-key" |> build_conn() |> McpAuth.call(@opts)
      refute conn.halted
    end

    test "passes through with no header" do
      Application.put_env(:edge_admin, :auth_enabled, false)
      conn = nil |> build_conn() |> McpAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — valid master key" do
    test "passes through with correct master key" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = "Bearer master-key" |> build_conn() |> McpAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — valid mcp key" do
    test "passes through with correct mcp key" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = "Bearer mcp-key" |> build_conn() |> McpAuth.call(@opts)
      refute conn.halted
    end

    test "passes through when mcp_key equals master_key (default fallback)" do
      Application.put_env(:edge_admin, :master_key, "shared-key")
      Application.put_env(:edge_admin, :mcp_key, "shared-key")
      conn = "Bearer shared-key" |> build_conn() |> McpAuth.call(@opts)
      refute conn.halted
    end
  end

  describe "auth enabled — invalid key" do
    test "halts with 401 when key is wrong" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = "Bearer wrong-key" |> build_conn() |> McpAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when no Authorization header" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = nil |> build_conn() |> McpAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "halts with 401 when scheme is not Bearer" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = "Token mcp-key" |> build_conn() |> McpAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end

    test "response body has error.code = unauthorized" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = "Bearer wrong" |> build_conn() |> McpAuth.call(@opts)
      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["error", "code"]) == "unauthorized"
    end

    test "response body has error key" do
      Application.put_env(:edge_admin, :master_key, "master-key")
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = "Bearer wrong" |> build_conn() |> McpAuth.call(@opts)
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end
  end

  describe "auth_enabled defaults to true" do
    test "when :auth_enabled not set, auth is enforced" do
      Application.delete_env(:edge_admin, :auth_enabled)
      Application.put_env(:edge_admin, :mcp_key, "mcp-key")
      conn = nil |> build_conn() |> McpAuth.call(@opts)
      assert conn.halted
      assert conn.status == 401
    end
  end
end
