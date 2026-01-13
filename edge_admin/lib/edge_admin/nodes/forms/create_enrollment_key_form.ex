# edge_admin/lib/edge_admin/nodes/forms/create_enrollment_key_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateEnrollmentKeyForm do
  @moduledoc """
  Form for validating enrollment key creation inputs.

  Handles input validation for creating enrollment keys (default or custom).
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:key_type, :string)
    field(:expiration, :integer)
    field(:uses_remaining, :integer)
  end

  @doc """
  Validates and normalizes enrollment key creation parameters.

  ## Validations
  - `key_type` - Required, must be "default" or "custom"
  - `expiration` - Optional, must be positive integer in seconds (default: 3600)
  - `uses_remaining` - Optional, must be positive integer (default: 1)

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(%{"enrollment_key" => key_attrs}) when is_map(key_attrs) do
    # Unwrap enrollment_key
    changeset(key_attrs)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:key_type, :expiration, :uses_remaining])
    |> validate_required([:key_type])
    |> validate_inclusion(:key_type, ["default", "custom"])
    |> validate_number(:expiration, greater_than: 0)
    |> validate_number(:uses_remaining, greater_than: 0)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:enrollment_key, "is required")
     |> apply_action!(:insert)}
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "key_type" => form.key_type,
      "expiration" => form.expiration,
      "uses_remaining" => form.uses_remaining
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
