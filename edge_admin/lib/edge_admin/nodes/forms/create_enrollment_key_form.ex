# edge_admin/lib/edge_admin/nodes/forms/create_enrollment_key_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateEnrollmentKeyForm do
  @moduledoc false
  use EdgeAdmin.Form

  embedded_schema do
    field(:name, :string)
    field(:uses_remaining, :integer)
    field(:expired_at, :utc_datetime)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :uses_remaining, :expired_at])
    |> validate_uses_remaining()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(attrs, form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_), do: changeset(%{})

  defp validate_uses_remaining(changeset) do
    validate_change(changeset, :uses_remaining, fn _, value ->
      if value > 0 do
        []
      else
        [uses_remaining: "must be a positive integer (or null for unlimited)"]
      end
    end)
  end

  # Preserve explicit null (key present, value nil) vs omitted (key absent).
  # null -> unlimited (uses_remaining: nil in DB)
  # omitted -> DB default of 1
  defp to_map(raw_attrs, %__MODULE__{} = form) do
    %{}
    |> maybe_put(raw_attrs, "name", form.name)
    |> maybe_put(raw_attrs, "uses_remaining", form.uses_remaining)
    |> maybe_put(raw_attrs, "expired_at", form.expired_at)
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
