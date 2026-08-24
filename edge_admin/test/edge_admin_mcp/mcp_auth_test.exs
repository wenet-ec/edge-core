# edge_admin/test/edge_admin_mcp/mcp_auth_test.exs
defmodule EdgeAdminMcp.Middlewares.McpAuthTest do
  use ExUnit.Case, async: false

  alias EdgeAdminMcp.Middlewares.McpAuth

  setup do
    Application.put_env(:edge_admin, :mcp_auth_enabled, true)
    Application.put_env(:edge_admin, :master_key, "master-key")
    Application.put_env(:edge_admin, :mcp_key, "mcp-key")

    on_exit(fn ->
      Application.delete_env(:edge_admin, :mcp_auth_enabled)
      Application.delete_env(:edge_admin, :master_key)
      Application.delete_env(:edge_admin, :mcp_key)
    end)
  end

  test "accepts the MCP and master bearer tokens" do
    assert McpAuth.status(%{"authorization" => "Bearer mcp-key"}) == :authenticated
    assert McpAuth.status(%{"authorization" => "Bearer master-key"}) == :authenticated
  end

  test "allows missing credentials as anonymous" do
    assert McpAuth.status(%{}) == :anonymous
  end

  test "rejects invalid credentials" do
    assert McpAuth.status(%{"authorization" => "Bearer wrong-key"}) == :invalid
    assert McpAuth.status(%{"authorization" => "Basic mcp-key"}) == :invalid
  end

  test "auth disabled treats the request as authenticated" do
    Application.put_env(:edge_admin, :mcp_auth_enabled, false)
    assert McpAuth.status(%{}) == :authenticated
  end
end
