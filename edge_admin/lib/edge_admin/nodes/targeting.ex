# edge_admin/lib/edge_admin/nodes/targeting.ex
defmodule EdgeAdmin.Nodes.Targeting do
  @moduledoc """
  Targeting — schema *and* resolver for "which subset of the fleet" selection.

  Used by any operation that addresses one or more nodes via flexible
  selection — currently `Commands.create_command` and
  `SelfUpdates.create_self_update_request`. Future fleet-wide operations
  should reference this module rather than duplicate the shape or the
  resolution logic.

  This module has two responsibilities:

  1. **Input shape** (`peri_schema/0`, `validate_iso8601_date_or_datetime/1`)
     — the canonical layer-1 (public-API gate) Peri schema. Used by MCP tool
     definitions and mirrored by the OpenApiSpex schemas on the REST side.
  2. **Resolution** (`nodes_for_all/2`, `nodes_for_ids/2`,
     `nodes_for_clusters/3`) — at runtime, turns a validated targeting spec
     into the concrete list of nodes the operation should run against. Pages
     through `Nodes.list_nodes/1` and `Nodes.list_clusters/1` and intersects
     the results.

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

  The schema half is the canonical layer-1 (public-API gate) shape — see
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

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node

  require Logger

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

  @doc """
  Resolves the `"all"` targeting type — returns every node matching
  `node_filters` (optionally further restricted to clusters matching
  `cluster_filters`).
  """
  @spec nodes_for_all(map(), map()) :: [Node.t()]
  def nodes_for_all(node_filters, cluster_filters) do
    all_filtered_nodes(node_filters, cluster_filters)
  end

  @doc """
  Resolves the `"nodes"` targeting type — returns the nodes for the given ids,
  optionally narrowed by `node_filters`.

  Non-existent ids are silently dropped.
  """
  @spec nodes_for_ids([String.t()], map()) :: [Node.t()]
  def nodes_for_ids(node_ids, node_filters) do
    unique_node_ids = Enum.uniq(node_ids)

    nodes =
      unique_node_ids
      |> Nodes.get_nodes_by_ids()
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, node} -> node end)

    if map_size(node_filters) == 0 do
      nodes
    else
      # Apply node_filters as an intersection — only keep ids that also appear
      # in the filtered list. No cluster_filters for this targeting type.
      all_matching_nodes = all_filtered_nodes(node_filters, %{})
      matching_node_ids = MapSet.new(all_matching_nodes, & &1.id)

      Enum.filter(nodes, fn node ->
        MapSet.member?(matching_node_ids, node.id)
      end)
    end
  end

  @doc """
  Resolves the `"clusters"` targeting type — returns `{nodes, cluster_id}`
  where `cluster_id` is set when exactly one cluster matches, `nil` otherwise.

  `cluster_filters` AND `cluster_names` (intersection): a cluster must appear
  in both to contribute its nodes.
  """
  @spec nodes_for_clusters([String.t()], map(), map()) :: {[Node.t()], String.t() | nil}
  def nodes_for_clusters(cluster_names, node_filters, cluster_filters) do
    unique_cluster_names = Enum.uniq(cluster_names)

    clusters =
      unique_cluster_names
      |> Enum.map(&Nodes.get_cluster/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, cluster} -> cluster end)

    if Enum.empty?(clusters) do
      Logger.warning("No valid clusters found from names: #{inspect(unique_cluster_names)}")
      {[], nil}
    else
      filtered_clusters =
        if map_size(cluster_filters) > 0 do
          filtered_cluster_names = all_filtered_cluster_names(cluster_filters)
          filtered_set = MapSet.new(filtered_cluster_names)

          Enum.filter(clusters, fn cluster ->
            MapSet.member?(filtered_set, cluster.name)
          end)
        else
          clusters
        end

      if Enum.empty?(filtered_clusters) do
        Logger.info("No clusters match the combined cluster_names AND cluster_filters")
        {[], nil}
      else
        cluster_id =
          case filtered_clusters do
            [single_cluster] -> single_cluster.id
            _ -> nil
          end

        cluster_names_list = Enum.map(filtered_clusters, & &1.name)
        nodes = nodes_from_cluster_list(cluster_names_list, node_filters)

        {nodes, cluster_id}
      end
    end
  end

  # Pages through Nodes.list_clusters/1 to collect every cluster name matching
  # the given cluster_filters.
  defp all_filtered_cluster_names(cluster_filters, page \\ 1, accumulated_names \\ []) do
    params =
      cluster_filters
      |> Map.put("page_size", "1000")
      |> Map.put("page", to_string(page))

    case Nodes.list_clusters(params) do
      {:ok, {clusters, meta}} ->
        all_names = accumulated_names ++ Enum.map(clusters, & &1.name)

        if meta.has_next_page? do
          all_filtered_cluster_names(cluster_filters, page + 1, all_names)
        else
          all_names
        end

      {:error, _meta} ->
        Logger.error("Failed to list clusters with filters: #{inspect(cluster_filters)}")
        accumulated_names
    end
  end

  # Pages through Nodes.list_nodes/1 and intersects the result with the given
  # cluster names.
  defp nodes_from_cluster_list(cluster_names, node_filters, page \\ 1, accumulated_nodes \\ []) do
    cluster_name_set = MapSet.new(cluster_names)

    params =
      node_filters
      |> Map.put("page_size", "1000")
      |> Map.put("page", to_string(page))

    case Nodes.list_nodes(params) do
      {:ok, {nodes, meta}} ->
        filtered_nodes =
          Enum.filter(nodes, fn node ->
            MapSet.member?(cluster_name_set, node.cluster.name)
          end)

        all_nodes = accumulated_nodes ++ filtered_nodes

        if meta.has_next_page? do
          nodes_from_cluster_list(cluster_names, node_filters, page + 1, all_nodes)
        else
          all_nodes
        end

      {:error, _meta} ->
        Logger.error("Failed to list nodes with filters: #{inspect(node_filters)}")
        accumulated_nodes
    end
  end

  # Pages through Nodes.list_nodes/1 to collect every node matching node_filters,
  # optionally narrowed to clusters matching cluster_filters. The cluster name
  # set is computed once on the first page and threaded through the recursion.
  defp all_filtered_nodes(node_filters, cluster_filters, page \\ 1, accumulated_nodes \\ [], cluster_names \\ nil) do
    cluster_names =
      cluster_names ||
        if map_size(cluster_filters) > 0 do
          all_filtered_cluster_names(cluster_filters)
        end

    params =
      node_filters
      |> Map.put("page_size", "100")
      |> Map.put("page", to_string(page))

    case Nodes.list_nodes(params) do
      {:ok, {nodes, meta}} ->
        filtered_nodes =
          if cluster_names do
            cluster_name_set = MapSet.new(cluster_names)

            Enum.filter(nodes, fn node ->
              MapSet.member?(cluster_name_set, node.cluster.name)
            end)
          else
            nodes
          end

        all_nodes = accumulated_nodes ++ filtered_nodes

        if meta.has_next_page? do
          all_filtered_nodes(
            node_filters,
            cluster_filters,
            page + 1,
            all_nodes,
            cluster_names
          )
        else
          all_nodes
        end

      {:error, _meta} ->
        Logger.error("Failed to list nodes with filters: #{inspect(node_filters)}")
        accumulated_nodes
    end
  end
end
