# edge_admin/lib/edge_admin/commands/forms/create_command_form.ex
defmodule EdgeAdmin.Commands.Forms.CreateCommandForm do
  @moduledoc """
  Form for validating command creation inputs.

  Handles input validation for creating commands with flexible targeting options.
  This form validates external API inputs before passing to the domain layer.
  """
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:targeting_type, :string)
    field(:node_ids, {:array, :binary_id})
    field(:cluster_names, {:array, :string})
  end

  @doc """
  Validates and normalizes command creation parameters.

  ## Validations
  - `command_text` - Required, must not be empty
  - `timeout` - Optional, must be positive integer in milliseconds
  - `targeting_type` - Required, must be "all", "nodes", or "clusters"
  - `node_ids` - Required if targeting_type is "nodes"
  - `cluster_names` - Required if targeting_type is "clusters"

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(%{"command" => command_attrs}) when is_map(command_attrs) do
    # Unwrap command
    changeset(command_attrs)
  end

  def changeset(attrs) when is_map(attrs) do
    # Extract targeting nested map if present
    targeting = Map.get(attrs, "targeting", %{})

    # Flatten targeting into top-level fields for validation
    flattened_attrs =
      attrs
      |> Map.put("targeting_type", Map.get(targeting, "type"))
      |> Map.put("node_ids", Map.get(targeting, "node_ids"))
      |> Map.put("cluster_names", Map.get(targeting, "cluster_names"))

    %__MODULE__{}
    |> cast(flattened_attrs, [:command_text, :timeout, :targeting_type, :node_ids, :cluster_names])
    |> validate_required([:command_text, :targeting_type])
    |> validate_command_text_format()
    |> validate_timeout()
    |> validate_targeting_type()
    |> validate_targeting_requirements()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form, attrs)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:command, "is required")
     |> apply_action!(:insert)}
  end

  defp validate_command_text_format(changeset) do
    validate_change(changeset, :command_text, fn :command_text, command_text ->
      trimmed = String.trim(command_text)

      if trimmed == "" do
        [command_text: "cannot be empty or only whitespace"]
      else
        []
      end
    end)
  end

  defp validate_timeout(changeset) do
    validate_change(changeset, :timeout, fn :timeout, timeout ->
      cond do
        is_nil(timeout) ->
          []

        timeout <= 0 ->
          [timeout: "must be a positive number (in milliseconds)"]

        true ->
          []
      end
    end)
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
    # Build the base command attrs
    base_attrs = %{
      "command_text" => form.command_text,
      "timeout" => form.timeout
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    # Get original targeting to preserve all fields
    original_targeting = Map.get(original_attrs, "targeting", %{})

    # Build base targeting with validated fields
    base_targeting =
      case form.targeting_type do
        "all" ->
          %{"type" => "all"}

        "nodes" ->
          %{"type" => "nodes", "node_ids" => form.node_ids}

        "clusters" ->
          %{"type" => "clusters", "cluster_names" => form.cluster_names}
      end

    # Merge original targeting with base targeting (base targeting takes precedence for validated fields)
    targeting = Map.merge(original_targeting, base_targeting)

    Map.put(base_attrs, "targeting", targeting)
  end
end
