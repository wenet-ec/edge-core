# edge_admin/lib/edge_admin/nodes/schemas/node_diagnostic.ex
defmodule EdgeAdmin.Nodes.Schemas.NodeDiagnostic do
  @moduledoc """
  Latest Agent diagnostic report for a node.
  """

  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Validators.NodeDiagnosticValidators

  @type t :: %__MODULE__{
          id: String.t(),
          node_id: String.t(),
          node: Node.t() | NotLoaded.t(),
          report: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "node_diagnostics" do
    field :report, :map

    belongs_to :node, Node

    timestamps()
  end

  @doc false
  def changeset(diagnostic, attrs) do
    diagnostic
    |> cast(attrs, [:node_id, :report])
    |> validate_required([:node_id, :report])
    |> validate_change(:report, fn :report, report ->
      report
      |> NodeDiagnosticValidators.errors()
      |> Enum.map(&{:report, &1})
    end)
    |> unique_constraint(:node_id, name: :node_diagnostics_node_id_index)
    |> foreign_key_constraint(:node_id)
  end
end
