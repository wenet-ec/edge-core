defmodule EdgeAdmin.Nodes.Forms.VerifyEnrollmentKeyForm do
  @moduledoc "Validates an enrollment key supplied by an Agent during bootstrap."
  use EdgeAdmin.Form

  embedded_schema do
    field(:key, :string)
  end

  @doc "Validates and normalizes an enrollment-key verification request."
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:key])
    |> validate_required([:key])
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, %{"key" => form.key}}
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
