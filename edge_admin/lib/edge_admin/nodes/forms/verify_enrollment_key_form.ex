defmodule EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyForm do
  @moduledoc "Validates an enrollment key supplied by an Agent during bootstrap."
  use EdgeAdmin.Form

  embedded_schema do
    field(:key, :string)
  end

  @doc "Validates an enrollment-key verification request and returns the key."
  @spec changeset(map()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t() | :invalid}
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
