# edge_admin/lib/edge_admin/nodes/forms/create_alias_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateAliasForm do
  @moduledoc """
  Form for validating alias creation inputs.

  Handles input validation for creating node aliases.
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Naming

  embedded_schema do
    field(:name, :string)
  end

  @doc """
  Validates and normalizes alias creation parameters.

  Note: node_id and cluster_id are validated at the controller level via path param
  and set by the context function.

  ## Validations
  - `name` - Required, must be lowercase alphanumeric with hyphens (DNS-compatible)

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: Naming.alias_name_max_length())
    |> validate_format(:name, Naming.alias_name_regex(),
      message: "must be lowercase alphanumeric with hyphens, no leading/trailing hyphens"
    )
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp to_map(%__MODULE__{} = form) do
    %{"name" => form.name}
  end
end
