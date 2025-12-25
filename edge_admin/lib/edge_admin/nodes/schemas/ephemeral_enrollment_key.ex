# edge_admin/lib/edge_admin/nodes/schemas/ephemeral_enrollment_key.ex
defmodule EdgeAdmin.Nodes.Schemas.EphemeralEnrollmentKey do
  @moduledoc """
  Tracks ephemeral enrollment keys for automatic cleanup.

  Ephemeral keys are used for:
  1. Staff troubleshooting - temporary VPN access, not registered in nodes table
  2. Ephemeral edge nodes - temporary nodes that ARE registered but should be cleaned up

  Permanent keys (production edge nodes) are NOT tracked in this table.

  The cleanup worker periodically queries Netmaker for hosts enrolled with tracked
  keys and deletes them after TTL expires.
  """
  use EdgeAdmin.Schema

  schema "ephemeral_enrollment_keys" do
    field(:token, :string)
    field(:tag, :string)
    field(:time_to_live, :integer)
    belongs_to(:cluster, EdgeAdmin.Nodes.Schemas.Cluster)

    timestamps()
  end

  @doc false
  def changeset(enrollment_key, attrs) do
    enrollment_key
    |> cast(attrs, [:token, :tag, :time_to_live, :cluster_id])
    |> validate_required([:token, :tag, :time_to_live, :cluster_id])
    |> validate_number(:time_to_live, greater_than: 0)
    |> unique_constraint(:token)
    |> foreign_key_constraint(:cluster_id)
  end
end
