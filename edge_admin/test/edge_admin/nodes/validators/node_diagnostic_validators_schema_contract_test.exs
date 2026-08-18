# edge_admin/test/edge_admin/nodes/validators/node_diagnostic_validators_schema_contract_test.exs
defmodule EdgeAdmin.Nodes.Validators.NodeDiagnosticValidatorsSchemaContractTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic

  test "the model schema applies the diagnostic validator" do
    changeset =
      NodeDiagnostic.changeset(%NodeDiagnostic{}, %{
        node_id: Ecto.UUID.generate(),
        report: %{"overall" => "unknown"}
      })

    refute changeset.valid?
    assert %{report: [_message | _]} = errors_on(changeset)
  end

  defp errors_on(changeset), do: Ecto.Changeset.traverse_errors(changeset, & &1)
end
