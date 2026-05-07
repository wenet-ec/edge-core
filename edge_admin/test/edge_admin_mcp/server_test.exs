# edge_admin/test/edge_admin_mcp/server_test.exs
defmodule EdgeAdminMcp.ServerTest do
  # async: true — Mox in private mode scopes stubs per test process, so
  # parallel tests don't race even when they touch the same mock.
  use ExUnit.Case, async: true

  import Mox

  alias EdgeAdminMcp.Server

  setup :verify_on_exit!

  defp request(name) do
    %{"method" => "tools/call", "params" => %{"name" => name}}
  end

  # ---------------------------------------------------------------------------
  # blocked_when_degraded/0 — pin the cross-surface mirror with REST's
  # DegradedMode :block actions. Adding a new write tool: mirror REST's
  # :block list, append here, then update this assertion.
  # ---------------------------------------------------------------------------

  describe "blocked_when_degraded/0" do
    test "is the documented set of write tools mirroring REST's :block actions" do
      assert Server.blocked_when_degraded() == [
               "create_cluster",
               "update_cluster",
               "delete_cluster",
               "change_node_cluster",
               "delete_node",
               "create_enrollment_key",
               "update_enrollment_key",
               "delete_enrollment_key",
               "create_self_update_request"
             ]
    end

    test "no duplicates" do
      list = Server.blocked_when_degraded()
      assert length(list) == length(Enum.uniq(list))
    end

    test "every entry follows the verb_resource snake_case convention" do
      for tool <- Server.blocked_when_degraded() do
        assert tool =~ ~r/\A[a-z]+_[a-z_]+\z/, "expected #{inspect(tool)} to be snake_case"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # check_not_degraded/1 — three branches:
  #   1. blocked tool + cluster degraded → :degraded
  #   2. blocked tool + cluster healthy  → :ok
  #   3. anything else (read tool, unknown method) → :ok (no Metadata call)
  # ---------------------------------------------------------------------------

  describe "check_not_degraded/1 — blocked tool, cluster degraded" do
    test "returns :degraded when degraded?() is true" do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> true end)

      for tool <- Server.blocked_when_degraded() do
        assert Server.check_not_degraded(request(tool)) == :degraded,
               "expected #{tool} to be blocked under degraded mode"
      end
    end
  end

  describe "check_not_degraded/1 — blocked tool, cluster healthy" do
    test "returns :ok when degraded?() is false" do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> false end)

      for tool <- Server.blocked_when_degraded() do
        assert Server.check_not_degraded(request(tool)) == :ok,
               "expected #{tool} to pass when cluster is healthy"
      end
    end
  end

  describe "check_not_degraded/1 — unblocked requests bypass the check" do
    test "read-only tool names return :ok without calling Metadata" do
      # No stub set up — if the function tries to call MetadataMock.degraded?,
      # Mox raises. That's the assertion: we must NOT consult metadata for
      # unblocked tools.
      assert Server.check_not_degraded(request("list_nodes")) == :ok
      assert Server.check_not_degraded(request("get_command")) == :ok
      assert Server.check_not_degraded(request("list_webhooks")) == :ok
    end

    test "non-tools/call methods return :ok without calling Metadata" do
      assert Server.check_not_degraded(%{"method" => "tools/list"}) == :ok
      assert Server.check_not_degraded(%{"method" => "initialize"}) == :ok
    end

    test "malformed requests fall through to the catch-all" do
      assert Server.check_not_degraded(%{}) == :ok
      assert Server.check_not_degraded(%{"method" => "tools/call"}) == :ok
      assert Server.check_not_degraded(%{"method" => "tools/call", "params" => %{}}) == :ok
    end
  end
end
