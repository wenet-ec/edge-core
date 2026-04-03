defmodule EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyForm do
  @moduledoc false
  use EdgeAdmin.Form

  embedded_schema do
    field(:key, :string)
  end

  def changeset(%{enrollment_key: key_attrs}) when is_map(key_attrs), do: changeset(key_attrs)

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:key])
    |> validate_required([:key])
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, form.key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_), do: {:error, :invalid}
end
