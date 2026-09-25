# edge_admin/test/edge_admin/nodes/validators/node_diagnostic_validators_schema_contract_test.exs
defmodule EdgeAdmin.Nodes.Validators.NodeDiagnosticValidatorsSchemaContractTest do
  use ExUnit.Case, async: true

  import EdgeAdmin.Test.ChangesetAssertions, only: [errors_on: 1]

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
end
