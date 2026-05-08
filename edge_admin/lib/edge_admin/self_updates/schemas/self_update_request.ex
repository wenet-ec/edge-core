# edge_admin/lib/edge_admin/self_updates/schemas/self_update_request.ex
defmodule EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest do
  @moduledoc """
  Schema for self-update requests.

  A self-update request triggers agent containers to update themselves via their
  self-update service (e.g., Watchtower). Requests are processed asynchronously
  by an Oban worker.

  ## Fields
  - `targeting` - JSON targeting configuration (same as commands)
  - `status` - Request status: `:pending`, `:processing`, `:completed`
  - `summary` - JSON summary of results: %{total, triggered, failed}
  """
  use EdgeAdmin.Schema

  # Status registry. Schema's Ecto.Enum, registry helpers, and external
  # surfaces (controller / MCP / OpenAPI / AsyncAPI enums) all derive from
  # these lists — single source of truth.
  @statuses [:pending, :processing, :completed]

  @type status :: :pending | :processing | :completed

  @type t :: %__MODULE__{
          id: String.t(),
          targeting: map(),
          status: status(),
          summary: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @derive {
    Flop.Schema,
    filterable: [:status, :inserted_at, :updated_at],
    sortable: [:inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "self_update_requests" do
    field(:targeting, :map)
    field(:status, Ecto.Enum, values: @statuses, default: :pending)
    field(:summary, :map)

    timestamps()
  end

  @doc false
  def changeset(self_update_request, attrs) do
    self_update_request
    |> cast(attrs, [:targeting, :status, :summary])
    |> validate_required([:targeting])
  end

  # ---------------------------------------------------------------------------
  # Status registry
  # ---------------------------------------------------------------------------

  @doc "All request statuses, in canonical lifecycle order."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Wire-format strings (sorted to match `statuses/0`). For OpenAPI / MCP / AsyncAPI enums."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)
end
