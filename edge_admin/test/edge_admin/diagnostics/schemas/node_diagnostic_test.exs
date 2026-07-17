# edge_admin/test/edge_admin/diagnostics/schemas/node_diagnostic_test.exs
defmodule EdgeAdmin.Diagnostics.Schemas.NodeDiagnosticTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Diagnostics.Schemas.NodeDiagnostic

  defp valid_attrs(overrides) do
    Map.merge(
      %{
        node_id: Ecto.UUID.generate(),
        report: %{"collected_at" => "2026-07-17T00:00:00Z", "overall" => "pass", "checks" => []}
      },
      overrides
    )
  end

  test "accepts a valid fallback diagnostic report" do
    assert NodeDiagnostic.changeset(%NodeDiagnostic{}, valid_attrs(%{})).valid?
  end

  test "requires a node and report" do
    changeset = NodeDiagnostic.changeset(%NodeDiagnostic{}, %{})
    refute changeset.valid?
    errors = errors_on(changeset)
    assert "can't be blank" in errors[:node_id]
    assert "can't be blank" in errors[:report]
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
