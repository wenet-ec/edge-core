# edge_admin/test/edge_admin_mcp/middlewares/mcp_auth_test.exs
defmodule EdgeAdminMcp.Middlewares.McpAuthTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.Test.AppConfig
  alias EdgeAdminMcp.Middlewares.McpAuth

  setup do
    AppConfig.restore_on_exit(:edge_admin, [:mcp_auth_enabled, :master_key, :mcp_key])
    Elixir.Application.put_env(:edge_admin, :mcp_auth_enabled, true)
    Elixir.Application.put_env(:edge_admin, :master_key, "master-key")
    Elixir.Application.put_env(:edge_admin, :mcp_key, "mcp-key")
    :ok
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
    Elixir.Application.put_env(:edge_admin, :mcp_auth_enabled, false)
    assert McpAuth.status(%{}) == :authenticated
  end
end
