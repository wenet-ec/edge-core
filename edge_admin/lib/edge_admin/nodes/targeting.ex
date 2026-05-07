# edge_admin/lib/edge_admin/nodes/targeting.ex
defmodule EdgeAdmin.Nodes.Targeting do
  @moduledoc """
  Shared layer-1 schema for "which subset of the fleet" targeting.

  Used by any operation that addresses one or more nodes via flexible
  selection — currently `Commands.create_command` and
  `SelfUpdates.create_self_update_request`. Future fleet-wide operations
  should reference this schema rather than duplicate the shape.

  ## Shape

  - `type` — required, one of `"all"` | `"nodes"` | `"clusters"`.
  - `node_ids` — list of node UUID strings. Required when `type = "nodes"`,
    ignored otherwise.
  - `cluster_names` — list of cluster name strings. Required when
    `type = "clusters"`, ignored otherwise.
  - `node_filters` — optional object further refining the target nodes
    (AND logic with selection above). All keys optional.
  - `cluster_filters` — optional object further refining the target
    clusters (AND logic). Only meaningful when `type = "clusters"` or
    `type = "all"`. All keys optional.

  ## Layering

  This module is the canonical layer-1 (public-API gate) shape — see
  `CLAUDE.md` for the defense-in-depth model. It validates *structural*
  shape including **strict ISO 8601 format** for the datetime range
  fields. It does **not** enforce conditional rules ("`node_ids` is
  required when `type = nodes`") — those are layer-2 (Form) checks, kept
  independent on purpose.

  The MCP layer consumes `peri_schema/0` directly via Anubis's
  `field :targeting, {:required, EdgeAdmin.Nodes.Targeting.peri_schema()}`.
  The REST OpenApiSpex schema is currently maintained in parallel
  (`EdgeAdminWeb.Schemas.Commands.CommandSchemas.CommandCreateRequest`
  and `EdgeAdminWeb.Schemas.SelfUpdates.SelfUpdateRequestSchemas.SelfUpdateRequestCreateRequest`)
  with a comment pointing here — auto-generation from this module is a
  future standardization step.
  """

  # The `__gte`/`__lte` fields accept ISO 8601 *date* OR *datetime* strings
  # (matching the OpenApiSpex `anyOf: [date-time, date]` shape on the REST
  # side). The custom validator preserves the original string — we don't
  # promote to %DateTime{}/%Date{} because the values get JSON-serialised
  # into JSONB and read back as strings; keeping them as strings end-to-end
  # avoids round-trip surprises.
  #
  # Trade-off: Peri's JSON Schema generator emits `{}` (true schema) for
  # `:custom` validators, so the model-facing JSON Schema doesn't advertise
  # the ISO 8601 requirement — the model must learn it from the docstring.
  # We accept this for stricter runtime validation: malformed dates get
  # rejected at layer 1 with a clean error rather than silently passing
  # through to the worker.
  @datetime_or_date {:custom, {__MODULE__, :validate_iso8601_date_or_datetime}}

  @node_filters_schema %{
    id_type: {:enum, ["persistent", "random"]},
    status: {:enum, ["healthy", "unhealthy", "unreachable"]},
    cluster_name: :string,
    version: :string,
    self_update_enabled: :boolean,
    last_seen_at__gte: @datetime_or_date,
    last_seen_at__lte: @datetime_or_date,
    inserted_at__gte: @datetime_or_date,
    inserted_at__lte: @datetime_or_date,
    updated_at__gte: @datetime_or_date,
    updated_at__lte: @datetime_or_date
  }

  @cluster_filters_schema %{
    name: :string,
    ipv4_range: :string,
    node_count: :integer,
    node_count__gte: :integer,
    node_count__lte: :integer,
    has_node_limit: :boolean,
    inserted_at__gte: @datetime_or_date,
    inserted_at__lte: @datetime_or_date,
    updated_at__gte: @datetime_or_date,
    updated_at__lte: @datetime_or_date
  }

  @schema %{
    type: {:required, {:enum, ["all", "nodes", "clusters"]}},
    node_ids: {:list, :string},
    cluster_names: {:list, :string},
    node_filters: @node_filters_schema,
    cluster_filters: @cluster_filters_schema
  }

  @doc """
  Returns the canonical Peri schema for targeting input. Embed in MCP
  tool schemas via:

      field :targeting, {:required, EdgeAdmin.Nodes.Targeting.peri_schema()}
  """
  @spec peri_schema() :: map()
  def peri_schema, do: @schema

  @doc """
  Validates an ISO 8601 date or datetime string. Returns the original
  string on success (no promotion to `%DateTime{}` / `%Date{}`).

  Used as a Peri `{:custom, _}` validator for the targeting schema's
  `__gte`/`__lte` filter fields, matching OpenApiSpex's
  `anyOf: [date-time, date]` shape on the REST side.
  """
  @spec validate_iso8601_date_or_datetime(term()) ::
          {:ok, String.t()} | {:error, String.t(), keyword()}
  def validate_iso8601_date_or_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _, _} ->
        {:ok, value}

      _ ->
        case Date.from_iso8601(value) do
          {:ok, _} -> {:ok, value}
          _ -> {:error, "expected ISO 8601 date or datetime string, got %{value}", value: inspect(value)}
        end
    end
  end

  def validate_iso8601_date_or_datetime(value) do
    {:error, "expected ISO 8601 date or datetime string, got %{value}", value: inspect(value)}
  end
end
