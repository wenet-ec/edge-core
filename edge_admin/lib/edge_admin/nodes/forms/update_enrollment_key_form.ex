# edge_admin/lib/edge_admin/nodes/forms/update_enrollment_key_form.ex
defmodule EdgeAdmin.Nodes.Forms.UpdateEnrollmentKeyForm do
  @moduledoc "Validates attributes for updating an Admin enrollment key."
  use EdgeAdmin.Form

  alias EdgeAdmin.Nodes.Validators.EnrollmentKeyValidators

  embedded_schema do
    field(:name, :string)
    field(:uses_remaining, :integer)
    field(:expires_at, :utc_datetime)
  end

  @doc "Validates and normalizes enrollment-key update attributes."
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :uses_remaining, :expires_at])
    |> validate_uses_remaining()
    |> validate_expires_at()
    |> apply_action(:update)
    |> case do
      {:ok, form} -> {:ok, to_map(attrs, form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :update}}
  end

  defp validate_uses_remaining(changeset) do
    validate_change(changeset, :uses_remaining, fn _, value ->
      if EnrollmentKeyValidators.valid_uses_remaining?(value) do
        []
      else
        [uses_remaining: "must be a positive integer (or null for unlimited)"]
      end
    end)
  end

  defp validate_expires_at(changeset) do
    validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if EnrollmentKeyValidators.valid_expiry?(expires_at, DateTime.utc_now()) do
        []
      else
        [expires_at: "must be in the future"]
      end
    end)
  end

  # Preserve explicit null (key present, value nil) vs omitted (key absent)
  defp to_map(raw_attrs, %__MODULE__{} = form) do
    %{}
    |> maybe_put(raw_attrs, "name", form.name)
    |> maybe_put(raw_attrs, "uses_remaining", form.uses_remaining)
    |> maybe_put(raw_attrs, "expires_at", form.expires_at)
  end

  defp maybe_put(result, raw_attrs, key, value) do
    atom_key = String.to_existing_atom(key)

    if Map.has_key?(raw_attrs, key) or Map.has_key?(raw_attrs, atom_key) do
      Map.put(result, key, value)
    else
      result
    end
  end
end
