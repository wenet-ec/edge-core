# edge_admin/lib/edge_admin/nodes/forms/change_node_cluster_form.ex
defmodule EdgeAdmin.Nodes.Forms.ChangeNodeClusterForm do
  @moduledoc """
  Form for validating node cluster change inputs.

  Handles input validation for changing a node's cluster assignment.
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Naming

  embedded_schema do
    field(:cluster_name, :string)
  end

  @doc """
  Validates and normalizes node cluster change parameters.

  ## Validations
  - `cluster_name` - Required, must match the cluster-name pattern in `EdgeAdmin.Naming`
  - Also checks if cluster exists (via get_cluster_fn callback)

  ## Returns
  - `{:ok, cluster_name}` - Validated cluster name as string
  - `{:error, changeset}` - Validation errors
  """
  def changeset(attrs, get_cluster_fn \\ &EdgeAdmin.Nodes.get_cluster/1)

  def changeset(attrs, get_cluster_fn) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:cluster_name])
    |> validate_required([:cluster_name])
    |> validate_length(:cluster_name, max: Naming.cluster_name_max_length())
    |> validate_format(:cluster_name, Naming.cluster_name_regex(),
      message: "must be lowercase alphanumeric with hyphens, cannot start/end with hyphen"
    )
    |> validate_cluster_exists(get_cluster_fn)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, form.cluster_name}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params, _get_cluster_fn) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_cluster_exists(changeset, get_cluster_fn) do
    cluster_name = get_field(changeset, :cluster_name)

    if cluster_name && changeset.valid? do
      case get_cluster_fn.(cluster_name) do
        {:ok, _cluster} -> changeset
        {:error, :not_found} -> add_error(changeset, :cluster_name, "not found")
      end
    else
      changeset
    end
  end
end
