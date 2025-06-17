# edge_admin/lib/edge_admin/commands/command.ex
defmodule EdgeAdmin.Commands.Command do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "commands" do
    field :commands, {:array, :string}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:commands])
    |> validate_required([:commands])
  end
end
