# edge_admin/lib/edge_admin/self_updates/forms/create_self_update_request_form.ex
defmodule EdgeAdmin.SelfUpdates.Forms.CreateSelfUpdateRequestForm do
  @moduledoc """
  Form for validating self-update request creation inputs.

  Validates external API input before passing it to the domain layer.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:targeting_type, :string)
    field(:node_ids, {:array, :binary_id})
    field(:cluster_names, {:array, :string})
  end

  @doc """
  Validates and normalizes self-update request creation parameters.

  `targeting.type` must be `"all"`, `"nodes"`, or `"clusters"`.
  Node and cluster targets must include their corresponding identifier lists.
  """
  def changeset(attrs) when is_map(attrs) do
    # Normalize to string keys so Ecto never sees a mixed-key map
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    targeting =
      attrs
      |> Map.get("targeting", %{})
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    flattened_attrs =
      %{}
      |> Map.put("targeting_type", Map.get(targeting, "type"))
      |> Map.put("node_ids", Map.get(targeting, "node_ids"))
      |> Map.put("cluster_names", Map.get(targeting, "cluster_names"))

    %__MODULE__{}
    |> cast(flattened_attrs, [:targeting_type, :node_ids, :cluster_names])
    |> validate_required([:targeting_type])
    |> validate_targeting_type()
    |> validate_targeting_requirements()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form, attrs)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:targeting, "is required")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_targeting_type(changeset) do
    validate_inclusion(changeset, :targeting_type, ["all", "nodes", "clusters"])
  end

  defp validate_targeting_requirements(changeset) do
    targeting_type = get_field(changeset, :targeting_type)
    node_ids = get_field(changeset, :node_ids)
    cluster_names = get_field(changeset, :cluster_names)

    case targeting_type do
      "nodes" ->
        if is_nil(node_ids) or node_ids == [] do
          add_error(changeset, :node_ids, "is required when targeting_type is 'nodes'")
        else
          changeset
        end

      "clusters" ->
        if is_nil(cluster_names) or cluster_names == [] do
          add_error(changeset, :cluster_names, "is required when targeting_type is 'clusters'")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp to_map(%__MODULE__{} = form, original_attrs) do
    original_targeting = Map.get(original_attrs, "targeting", %{})

    base_targeting =
      case form.targeting_type do
        "all" ->
          %{"type" => "all"}

        "nodes" ->
          %{"type" => "nodes", "node_ids" => form.node_ids}

        "clusters" ->
          %{"type" => "clusters", "cluster_names" => form.cluster_names}
      end

    targeting = Map.merge(original_targeting, base_targeting)

    %{"targeting" => targeting}
  end
end
