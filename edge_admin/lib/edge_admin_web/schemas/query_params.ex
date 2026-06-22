# edge_admin/lib/edge_admin_web/schemas/query_params.ex
defmodule EdgeAdminWeb.Schemas.QueryParams do
  @moduledoc """
  Reusable OpenAPI parameter specs for list endpoints.

  Every `:index` action shares the same pagination + sort conventions, plus a
  small set of repeated filter shapes (`field`, `field__gte`, `field__lte`,
  `has_field`). This module captures them so semantics stay consistent.

  ## Usage

      operation(:index,
        parameters:
          QueryParams.pagination() ++
            QueryParams.sort(order_by_example: "inserted_at,name", order_directions_example: "desc,asc") ++
            [
              QueryParams.string_filter(:name, description: "Filter by cluster name"),
              QueryParams.int_range_filter(:node_count),
              QueryParams.boolean_filter(:has_node_limit, description: "..."),
              QueryParams.datetime_range_filter(:inserted_at)
            ],
        responses: %{...}
      )

  ## Convention

  All helpers return a keyword-list slice that can be appended via `++`. Names
  are atoms — OpenApiSpex serialises them to strings.
  """

  alias OpenApiSpex.Schema

  # ---------------------------------------------------------------------------
  # Pagination + sort — included on every list endpoint
  # ---------------------------------------------------------------------------

  @doc """
  Pagination parameters: `page`, `page_size`.

  ## Options

    * `:default_page_size` — default value for `page_size` (default `20`)
    * `:max_page_size` — upper bound for `page_size` (default `100`)
  """
  @spec pagination(keyword()) :: keyword()
  def pagination(opts \\ []) do
    default_page_size = Keyword.get(opts, :default_page_size, 20)
    max_page_size = Keyword.get(opts, :max_page_size, 100)

    [
      page: [
        in: :query,
        description: "Page number (1-indexed)",
        schema: %Schema{type: :integer, minimum: 1, default: 1},
        example: 1
      ],
      page_size: [
        in: :query,
        description: "Items per page",
        schema: %Schema{type: :integer, minimum: 1, maximum: max_page_size, default: default_page_size},
        example: default_page_size
      ]
    ]
  end

  @doc """
  Sort parameters: `order_by`, `order_directions`.

  ## Options

    * `:order_by_example` — example value for `order_by` (default `"inserted_at"`)
    * `:order_directions_example` — example value for `order_directions` (default `"desc"`)
  """
  @spec sort(keyword()) :: keyword()
  def sort(opts \\ []) do
    order_by_example = Keyword.get(opts, :order_by_example, "inserted_at")
    order_directions_example = Keyword.get(opts, :order_directions_example, "desc")

    [
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %Schema{type: :string},
        example: order_by_example
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %Schema{type: :string},
        example: order_directions_example
      ]
    ]
  end

  # ---------------------------------------------------------------------------
  # Filter helpers — one keyword pair per filter
  # ---------------------------------------------------------------------------

  @doc """
  String exact-match or wildcard filter: `name` accepts `"prod-east"`,
  `"prod*"`, `"*east"`, or `"*east*"`. For multi-value (IN) matching use
  `string_in_filter/2` (`name__in=a,b`).
  """
  @spec string_filter(atom(), keyword()) :: {atom(), keyword()}
  def string_filter(name, opts \\ []) when is_atom(name) do
    description =
      Keyword.get(opts, :description, "Filter by #{name} (exact match or wildcard: prefix*, *suffix, *substring*)")

    {name,
     [
       in: :query,
       description: description,
       schema: %Schema{type: :string}
     ]}
  end

  @doc """
  String IN filter: `name__in` accepts a comma-separated list of exact values
  (e.g. `cluster_name__in=prod,staging`). Maps to an IN query. No wildcards.
  """
  @spec string_in_filter(atom(), keyword()) :: {atom(), keyword()}
  def string_in_filter(name, opts \\ []) when is_atom(name) do
    key = :"#{name}__in"

    description =
      Keyword.get(
        opts,
        :description,
        "Filter by #{name} — comma-separated list of exact values (IN match, e.g. #{name}__in=a,b,c)"
      )

    {key,
     [
       in: :query,
       description: description,
       style: :form,
       explode: false,
       schema: %Schema{type: :array, items: %Schema{type: :string}}
     ]}
  end

  @doc """
  Enum filter — restrict to a single value from a finite list
  (e.g. `status=healthy`). For multi-value (IN) matching use
  `enum_in_filter/3` (`status__in=healthy,unhealthy`).
  """
  @spec enum_filter(atom(), [String.t()], keyword()) :: {atom(), keyword()}
  def enum_filter(name, values, opts \\ []) when is_atom(name) and is_list(values) do
    description = Keyword.get(opts, :description, "Filter by #{name}")

    {name,
     [
       in: :query,
       description: description,
       schema: %Schema{type: :string, enum: values}
     ]}
  end

  @doc """
  Enum IN filter: `name__in` accepts a comma-separated list of values from a
  finite set (e.g. `status__in=healthy,unhealthy`). Maps to an IN query.
  Single-value usage (`status__in=healthy`) is also valid.

  OpenAPI `style: :form, explode: false` signals the comma-separated encoding.
  """
  @spec enum_in_filter(atom(), [String.t()], keyword()) :: {atom(), keyword()}
  def enum_in_filter(name, values, opts \\ []) when is_atom(name) and is_list(values) do
    key = :"#{name}__in"

    description =
      Keyword.get(
        opts,
        :description,
        "Filter by #{name} — comma-separated list of values (IN match). Allowed values: #{Enum.join(values, ", ")}"
      )

    {key,
     [
       in: :query,
       description: description,
       style: :form,
       explode: false,
       schema: %Schema{type: :array, items: %Schema{type: :string, enum: values}}
     ]}
  end

  @doc """
  Enum array filter — **deprecated**. Use `enum_in_filter/3` instead.

  Kept for any call-sites not yet migrated. Emits `name__in` with the same
  semantics as `enum_in_filter/3`.
  """
  @spec enum_array_filter(atom(), [String.t()], keyword()) :: {atom(), keyword()}
  def enum_array_filter(name, values, opts \\ []) when is_atom(name) and is_list(values) do
    enum_in_filter(name, values, opts)
  end

  @doc """
  Boolean filter — typically used for "is this column set?" (e.g. `has_node_limit`).
  """
  @spec boolean_filter(atom(), keyword()) :: {atom(), keyword()}
  def boolean_filter(name, opts \\ []) when is_atom(name) do
    description = Keyword.get(opts, :description, "Filter by #{name}")

    {name,
     [
       in: :query,
       description: description,
       schema: %Schema{type: :boolean}
     ]}
  end

  @doc """
  UUID query filter — exact match (e.g. `command_id=<uuid>`).
  """
  @spec uuid_filter(atom(), keyword()) :: {atom(), keyword()}
  def uuid_filter(name, opts \\ []) when is_atom(name) do
    description = Keyword.get(opts, :description, "Filter by #{name}")

    {name,
     [
       in: :query,
       description: description,
       schema: %Schema{type: :string, format: :uuid}
     ]}
  end

  @doc """
  UUID IN filter: `name__in` accepts a comma-separated list of UUIDs
  (e.g. `node_id__in=uuid1,uuid2`). Maps to an IN query.
  OpenAPI `style: :form, explode: false` signals the comma-separated encoding.
  """
  @spec uuid_in_filter(atom(), keyword()) :: {atom(), keyword()}
  def uuid_in_filter(name, opts \\ []) when is_atom(name) do
    key = :"#{name}__in"

    description =
      Keyword.get(
        opts,
        :description,
        "Filter by #{name} — comma-separated list of UUIDs (IN match, e.g. #{name}__in=uuid1,uuid2)"
      )

    {key,
     [
       in: :query,
       description: description,
       style: :form,
       explode: false,
       schema: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
     ]}
  end

  @doc """
  UUID array filter — **deprecated**. Use `uuid_in_filter/2` instead.

  Kept for any call-sites not yet migrated. Delegates to `uuid_in_filter/2`.
  """
  @spec uuid_array_filter(atom(), keyword()) :: {atom(), keyword()}
  def uuid_array_filter(name, opts \\ []) when is_atom(name) do
    uuid_in_filter(name, opts)
  end

  @doc """
  String array filter — **deprecated**. Use `string_in_filter/2` instead.

  Kept for UUID array filters and any call-sites not yet migrated. Emits the
  key as-is (not `__in` suffixed) — only suitable for fields that are parsed
  as lists by `RequestParser` (e.g. when the value arrives pre-split).
  OpenAPI `style: :form, explode: false` signals the comma-separated encoding.
  """
  @spec string_array_filter(atom(), keyword()) :: {atom(), keyword()}
  def string_array_filter(name, opts \\ []) when is_atom(name) do
    description =
      Keyword.get(
        opts,
        :description,
        "Filter by #{name} — comma-separated list of values (exact IN match)"
      )

    {name,
     [
       in: :query,
       description: description,
       style: :form,
       explode: false,
       schema: %Schema{type: :array, items: %Schema{type: :string}}
     ]}
  end

  @doc """
  Integer equality filter — exact match.
  """
  @spec int_filter(atom(), keyword()) :: {atom(), keyword()}
  def int_filter(name, opts \\ []) when is_atom(name) do
    description = Keyword.get(opts, :description, "Filter by exact #{name} value")
    minimum = Keyword.get(opts, :minimum, 0)

    {name,
     [
       in: :query,
       description: description,
       schema: %Schema{type: :integer, minimum: minimum}
     ]}
  end

  @doc """
  Integer range filter pair: `name__gte` and `name__lte`.

  ## Options

    * `:minimum` — lower bound for both endpoints (default `0`)
    * `:gte_description`, `:lte_description` — override descriptions
  """
  @spec int_range_filter(atom(), keyword()) :: keyword()
  def int_range_filter(name, opts \\ []) when is_atom(name) do
    minimum = Keyword.get(opts, :minimum, 0)
    gte_description = Keyword.get(opts, :gte_description, "Filter by minimum #{name}")
    lte_description = Keyword.get(opts, :lte_description, "Filter by maximum #{name}")

    [
      {gte_key(name),
       [
         in: :query,
         description: gte_description,
         schema: %Schema{type: :integer, minimum: minimum}
       ]},
      {lte_key(name),
       [
         in: :query,
         description: lte_description,
         schema: %Schema{type: :integer, minimum: minimum}
       ]}
    ]
  end

  @doc """
  Datetime range filter pair: `name__gte` and `name__lte`. Accepts both ISO
  date-time and date-only forms (date is treated as start/end of day UTC).
  """
  @spec datetime_range_filter(atom(), keyword()) :: keyword()
  def datetime_range_filter(name, opts \\ []) when is_atom(name) do
    gte_description =
      Keyword.get(
        opts,
        :gte_description,
        "Filter records where #{name} is on or after this datetime " <>
          "(ISO 8601 datetime; date-only is treated as start of day UTC)"
      )

    lte_description =
      Keyword.get(
        opts,
        :lte_description,
        "Filter records where #{name} is on or before this datetime " <>
          "(ISO 8601 datetime; date-only is treated as end of day UTC)"
      )

    schema = %Schema{
      anyOf: [
        %Schema{type: :string, format: :"date-time"},
        %Schema{type: :string, format: :date}
      ]
    }

    [
      {gte_key(name), [in: :query, description: gte_description, schema: schema]},
      {lte_key(name), [in: :query, description: lte_description, schema: schema]}
    ]
  end

  defp gte_key(name), do: :"#{name}__gte"
  defp lte_key(name), do: :"#{name}__lte"
end
