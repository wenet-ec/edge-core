# edge_agent/lib/edge_agent/settings/setting.ex
defmodule EdgeAgent.Settings.Setting do
  @moduledoc false
  use EdgeAgent.Schema

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          key: String.t() | nil,
          value: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps()
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> validate_length(:key, min: 1, max: 255)
    |> unique_constraint(:key)
  end
end
