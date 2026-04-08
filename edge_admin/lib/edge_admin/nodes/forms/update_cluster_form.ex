# edge_admin/lib/edge_admin/nodes/forms/update_cluster_form.ex
defmodule EdgeAdmin.Nodes.Forms.UpdateClusterForm do
  @moduledoc """
  Form for validating cluster update inputs.

  Only fields explicitly provided are updated. To unset a nullable field, pass it as null.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:node_limit, :integer)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:node_limit])
    |> validate_node_limit()
    |> apply_action(:update)
    |> case do
      {:ok, form} -> {:ok, to_map(attrs, form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:base, "invalid parameters - expected a map")
     |> apply_action!(:update)}
  end

  defp validate_node_limit(changeset) do
    validate_number(changeset, :node_limit, greater_than: 0)
  end

  # Preserve explicit null (key present, value nil) vs omitted (key absent)
  defp to_map(raw_attrs, %__MODULE__{} = form) do
    result = %{}

    result =
      if Map.has_key?(raw_attrs, "node_limit") or Map.has_key?(raw_attrs, :node_limit) do
        Map.put(result, "node_limit", form.node_limit)
      else
        result
      end

    result
  end
end
