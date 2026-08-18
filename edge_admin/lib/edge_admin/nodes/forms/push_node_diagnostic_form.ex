# edge_admin/lib/edge_admin/nodes/forms/push_node_diagnostic_form.ex
defmodule EdgeAdmin.Nodes.Forms.PushNodeDiagnosticForm do
  @moduledoc """
  Validates an Agent-pushed diagnostic report.
  """

  use EdgeAdmin.Form

  alias EdgeAdmin.Nodes.Validators.NodeDiagnosticValidators

  embedded_schema do
    field(:diagnostic, :map)
  end

  @doc "Validates an Agent-pushed diagnostic payload."
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:diagnostic])
    |> validate_required([:diagnostic])
    |> validate_change(:diagnostic, &validate_diagnostic/2)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, %{"diagnostic" => form.diagnostic}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_attrs) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_diagnostic(:diagnostic, diagnostic) do
    diagnostic
    |> NodeDiagnosticValidators.errors()
    |> Enum.map(&{:diagnostic, &1})
  end
end
