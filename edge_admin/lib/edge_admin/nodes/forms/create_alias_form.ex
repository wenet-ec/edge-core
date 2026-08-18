# edge_admin/lib/edge_admin/nodes/forms/create_alias_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateAliasForm do
  @moduledoc """
  Form for validating alias creation inputs.

  Validates external API input before passing it to the domain layer.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Nodes.Validators.AliasValidators

  embedded_schema do
    field(:name, :string)
  end

  @doc """
  Validates and normalizes alias creation parameters.

  `node_id` and `cluster_id` come from path/context data, not this form.
  """
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_change(:name, fn :name, value ->
      if AliasValidators.valid_name?(value),
        do: [],
        else: [name: "must be lowercase alphanumeric with hyphens, no leading/trailing hyphens"]
    end)
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
