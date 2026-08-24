# edge_admin/test/edge_admin_mcp/server_test.exs
defmodule EdgeAdminMcp.ServerTest do
  # async: true — Mox in private mode scopes stubs per test process, so
  # parallel tests don't race even when they touch the same mock.
  use ExUnit.Case, async: false

  import Mox

  alias Anubis.Server.Context
  alias Anubis.Server.Frame
  alias EdgeAdminMcp.Middlewares.DegradedMode
  alias EdgeAdminMcp.Middlewares.McpAuth
  alias EdgeAdminMcp.ToolRegistry

  @blocked_tools ~w(
    create_cluster update_cluster delete_cluster change_node_cluster delete_node
    create_node_recovery_key delete_node_recovery_key create_enrollment_key
    create_default_enrollment_key update_enrollment_key delete_enrollment_key
    create_self_update_request
  )

  setup :verify_on_exit!

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

  defp request(name) do
    %{"method" => "tools/call", "params" => %{"name" => name}}
  end

  describe "degraded registration" do
    test "marks the REST-blocked tools with degraded: :block" do
      for tool <- @blocked_tools do
        assert ToolRegistry.degraded_behavior(tool) == :block
      end
    end

    test "defaults unannotated tools to degraded: :allow" do
      assert ToolRegistry.degraded_behavior("list_nodes") == :allow
      assert ToolRegistry.degraded_behavior("get_cluster") == :allow
    end
  end

  describe "anonymous MCP access" do
    test "does not expose anonymous tools until explicitly registered" do
      # DegradedMode.call/2 — three branches:
      #   1. blocked tool + cluster degraded → :degraded
      #   2. blocked tool + cluster healthy  → :ok
      #   3. anything else (read tool, unknown method) → :ok (no Metadata call)
      assert Enum.filter(ToolRegistry.scope_tools(), fn {scope, _name} -> scope == :public end) == []
    end

    test "requires authentication for tool calls" do
      request = request("list_nodes")
      assert {:error, _response, _frame} = McpAuth.call(request, Frame.new())
    end

    test "allows authenticated tool calls" do
      request = request("list_nodes")
      frame = %Frame{context: %Context{headers: %{"authorization" => "Bearer mcp-key"}}}
      assert McpAuth.call(request, frame) == :ok
    end
  end

  describe "DegradedMode.call/2 — blocked tool, cluster degraded" do
    test "returns :degraded when degraded?() is true" do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> true end)

      for tool <- @blocked_tools do
        assert {:error, _response, _frame} = DegradedMode.call(request(tool), Frame.new()),
               "expected #{tool} to be blocked under degraded mode"
      end
    end
  end

  describe "DegradedMode.call/2 — blocked tool, cluster healthy" do
    test "returns :ok when degraded?() is false" do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> false end)

      for tool <- @blocked_tools do
        assert DegradedMode.call(request(tool), Frame.new()) == :ok,
               "expected #{tool} to pass when cluster is healthy"
      end
    end
  end

  describe "DegradedMode.call/2 — unblocked requests bypass the check" do
    test "read-only tool names return :ok without calling Metadata" do
      # No stub set up — if the function tries to call MetadataMock.degraded?,
      # Mox raises. That's the assertion: we must NOT consult metadata for
      # unblocked tools.
      assert DegradedMode.call(request("list_nodes"), Frame.new()) == :ok
      assert DegradedMode.call(request("get_command"), Frame.new()) == :ok
      assert DegradedMode.call(request("list_webhooks"), Frame.new()) == :ok
    end

    test "non-tools/call methods return :ok without calling Metadata" do
      assert DegradedMode.call(%{"method" => "tools/list"}, Frame.new()) == :ok
      assert DegradedMode.call(%{"method" => "initialize"}, Frame.new()) == :ok
    end

    test "malformed requests fall through to the catch-all" do
      assert DegradedMode.call(%{}, Frame.new()) == :ok
      assert DegradedMode.call(%{"method" => "tools/call"}, Frame.new()) == :ok
      assert DegradedMode.call(%{"method" => "tools/call", "params" => %{}}, Frame.new()) == :ok
    end
  end
end
