# edge_admin/lib/edge_admin/nodes/ephemeral_enrollment_key.ex
defmodule EdgeAdmin.Nodes.EphemeralEnrollmentKey do
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
    belongs_to(:cluster, EdgeAdmin.Nodes.Cluster)

    timestamps()
  end

  @doc false
  def changeset(enrollment_key, attrs) do
    enrollment_key
    |> cast(attrs, [:token, :tag, :cluster_id])
    |> validate_required([:token, :tag, :cluster_id])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:cluster_id)
  end
end
