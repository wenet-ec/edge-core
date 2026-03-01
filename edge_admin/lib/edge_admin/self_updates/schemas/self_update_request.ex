# edge_admin/lib/edge_admin/self_updates/schemas/self_update_request.ex
defmodule EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest do
  @moduledoc """
  Schema for self-update requests.

  A self-update request triggers agent containers to update themselves via their
  self-update service (e.g., Watchtower). Requests are processed asynchronously
  by an Oban worker.

  ## Fields
  - `targeting` - JSON targeting configuration (same as commands)
  - `status` - Request status: "pending", "processing", "completed"
  - `summary` - JSON summary of results: %{total, triggered, failed}
  """
  use EdgeAdmin.Schema

  @type t :: %__MODULE__{}

  @derive {
    Flop.Schema,
    filterable: [:status, :inserted_at],
    sortable: [:inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "self_update_requests" do
    field(:targeting, :map)
    field(:status, :string, default: "pending")
    field(:summary, :map)

    timestamps()
  end

  @doc false
  def changeset(self_update_request, attrs) do
    self_update_request
    |> cast(attrs, [:targeting, :status, :summary])
    |> validate_required([:targeting])
    |> validate_inclusion(:status, ["pending", "processing", "completed"])
  end
end
