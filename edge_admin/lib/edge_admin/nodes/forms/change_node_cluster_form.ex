# edge_admin/lib/edge_admin/nodes/forms/change_node_cluster_form.ex
defmodule EdgeAdmin.Nodes.Forms.ChangeNodeClusterForm do
  @moduledoc """
  Form for validating node cluster change inputs.

  Validates external API input before passing it to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Nodes.Validators.ClusterValidators

  embedded_schema do
    field(:cluster_name, :string)
  end

  @doc """
  Validates and normalizes node cluster change parameters.

  Cluster existence is checked by the Nodes resource after this boundary
  validation succeeds.
  """

  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:cluster_name])
    |> validate_required([:cluster_name])
    |> validate_change(:cluster_name, fn :cluster_name, value ->
      cond do
        byte_size(value) > Naming.cluster_name_max_length() ->
          [cluster_name: "should be at most #{Naming.cluster_name_max_length()} character(s)"]

        not ClusterValidators.valid_name?(value) ->
          [cluster_name: "must be lowercase alphanumeric with hyphens, cannot start/end with hyphen"]

        true ->
          []
      end
    end)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, %{"cluster_name" => form.cluster_name}}
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
end
