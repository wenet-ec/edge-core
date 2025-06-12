# edge_agent/lib/edge_agent/settings/setting.ex
defmodule EdgeAgent.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
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
