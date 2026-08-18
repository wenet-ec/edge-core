# edge_admin/test/edge_admin/nodes/validators/node_diagnostic_validators_test.exs
defmodule EdgeAdmin.Nodes.Validators.NodeDiagnosticValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Validators.NodeDiagnosticValidators

  test "accepts a valid diagnostic report" do
    report = %{
      "collected_at" => "2026-01-01T00:00:00Z",
      "overall" => "pass",
      "checks" => [
        %{
          "name" => "bootstrap",
          "status" => "pass",
          "duration_ms" => 10,
          "details" => %{}
        }
      ]
    }

    assert NodeDiagnosticValidators.errors(report) == []
  end

  test "reports invalid diagnostic values" do
    errors = NodeDiagnosticValidators.errors(%{"overall" => "unknown"})
    assert "must include collected_at" in errors
    assert "overall must be pass, warn, or fail" in errors
    assert "must include checks" in errors
  end
end
