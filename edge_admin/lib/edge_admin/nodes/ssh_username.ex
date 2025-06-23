defmodule EdgeAdmin.Nodes.SshUsername do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ssh_usernames" do
    field(:username, :string)

    belongs_to(:node, EdgeAdmin.Nodes.Node)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ssh_username, attrs) do
    ssh_username
    |> cast(attrs, [:username, :node_id])
    |> validate_required([:username, :node_id])
    |> unique_constraint([:node_id, :username])
  end
end
