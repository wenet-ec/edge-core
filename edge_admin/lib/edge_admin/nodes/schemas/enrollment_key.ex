# edge_admin/lib/edge_admin/nodes/schemas/enrollment_key.ex
defmodule EdgeAdmin.Nodes.Schemas.EnrollmentKey do
  @moduledoc """
  Schema for cluster enrollment keys.

  Issued per cluster. Agents present the key to verify_enrollment before
  joining the VPN, ensuring the cluster has capacity before a VPN slot is consumed.

  The key is a base64-encoded JSON blob:

      base64({"admin_urls": ["https://admin.example.com"], "nonce": "<random_32_bytes_base64>"})

  Operators copy the full key blob into the agent's ENROLLMENT_KEY env var.
  The agent decodes it to extract admin_urls (for routing) and sends the full
  blob to the verify endpoint. Admin looks up by the blob directly.
  """
  use EdgeAdmin.Schema

  alias EdgeAdmin.Nodes.Schemas.Cluster

  @unlimited -1

  @derive {
    Flop.Schema,
    filterable: [:key, :uses_remaining, :expired_at, :last_used_at, :inserted_at, :updated_at],
    sortable: [:uses_remaining, :expired_at, :last_used_at, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          cluster_id: String.t(),
          cluster: Cluster.t() | Ecto.Association.NotLoaded.t(),
          uses_remaining: integer(),
          expired_at: DateTime.t() | nil,
          last_used_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "enrollment_keys" do
    field(:key, :string)
    field(:uses_remaining, :integer, default: 1)
    field(:expired_at, :utc_datetime)
    field(:last_used_at, :utc_datetime)

    belongs_to(:cluster, Cluster)

    timestamps()
  end

  @doc false
  def changeset(enrollment_key, attrs) do
    enrollment_key
    |> cast(attrs, [:key, :cluster_id, :uses_remaining, :expired_at])
    |> validate_required([:key, :cluster_id])
    |> validate_uses_remaining()
    |> unique_constraint(:key)
    |> assoc_constraint(:cluster)
  end

  @doc """
  Returns true if this key has been fully consumed (uses_remaining == 0).
  Keys with uses_remaining == -1 (unlimited) or > 0 are not spent.
  """
  @spec spent?(t()) :: boolean()
  def spent?(%__MODULE__{uses_remaining: 0}), do: true
  def spent?(%__MODULE__{}), do: false

  @doc """
  Returns true if this key has expired.
  Keys with no expired_at never expire.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expired_at: nil}), do: false

  def expired?(%__MODULE__{expired_at: expired_at}) do
    DateTime.after?(DateTime.utc_now(), expired_at)
  end

  @doc """
  Returns true if this key is unlimited use (uses_remaining == -1).
  """
  @spec unlimited?(t()) :: boolean()
  def unlimited?(%__MODULE__{uses_remaining: @unlimited}), do: true
  def unlimited?(%__MODULE__{}), do: false

  defp validate_uses_remaining(changeset) do
    validate_change(changeset, :uses_remaining, fn _, value ->
      if value == @unlimited or value > 0 do
        []
      else
        [uses_remaining: "must be -1 (unlimited) or a positive integer"]
      end
    end)
  end
end
