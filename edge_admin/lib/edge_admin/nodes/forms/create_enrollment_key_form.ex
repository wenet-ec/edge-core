# edge_admin/lib/edge_admin/nodes/forms/create_enrollment_key_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateEnrollmentKeyForm do
  @moduledoc false
  use EdgeAdmin.Form

  embedded_schema do
    field(:uses_remaining, :integer)
    field(:expired_at, :utc_datetime)
  end

  def changeset(%{enrollment_key: key_attrs}) when is_map(key_attrs), do: changeset(key_attrs)

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:uses_remaining, :expired_at])
    |> validate_uses_remaining()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
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

  defp to_map(%__MODULE__{} = form) do
    %{"uses_remaining" => form.uses_remaining, "expired_at" => form.expired_at}
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
