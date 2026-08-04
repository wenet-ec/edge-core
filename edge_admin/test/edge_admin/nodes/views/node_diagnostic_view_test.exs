# edge_admin/test/edge_admin/nodes/views/node_diagnostic_view_test.exs
defmodule EdgeAdmin.Nodes.Views.NodeDiagnosticViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Nodes.Views.NodeDiagnosticView

  describe "render/1" do
    test "renders the canonical public shape" do
      diagnostic = %{
        "collected_at" => "2026-07-17T10:30:00Z",
        "overall" => "pass",
        "checks" => [],
        "implementation_detail" => "not public"
      }

      rendered = NodeDiagnosticView.render(diagnostic)

      assert rendered == %{collected_at: "2026-07-17T10:30:00Z", overall: "pass", checks: []}
    end

    test "requires the diagnostic report shape" do
      assert_raise FunctionClauseError, fn ->
        NodeDiagnosticView.render(%{"overall" => "pass", "checks" => []})
      end
    end
  end

  describe "render_push/1" do
    test "renders the push acknowledgement" do
      updated_at = DateTime.truncate(DateTime.utc_now(), :second)

      diagnostic = %NodeDiagnostic{id: "diagnostic-uuid-1", node_id: "node-uuid-1", updated_at: updated_at}

      assert NodeDiagnosticView.render_push(diagnostic) == %{
               id: "diagnostic-uuid-1",
               node_id: "node-uuid-1",
               updated_at: updated_at
             }
    end
  end
end
