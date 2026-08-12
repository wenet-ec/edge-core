# edge_admin/lib/edge_admin_web/schemas/query_params.ex
defmodule EdgeAdminWeb.Schemas.QueryParams do
  @moduledoc """
  Reusable OpenAPI parameter specs for list endpoints.

  Every `:index` action shares the same pagination + sort conventions, plus a
  small set of repeated filter shapes (`field`, `field__gte`, `field__lte`,
  `has_field`). This module captures them so semantics stay consistent.

  All helpers return a keyword-list slice that can be appended via `++`. Names
  are atoms — OpenApiSpex serialises them to strings.

  `*_in_filter` helpers describe the wire format as a comma-separated string.
  OpenApiSpex can model `style=form, explode=false` arrays, but Swagger UI's
  enum-array control does not clear reliably for optional query parameters.
  Runtime parsing and validation still happen in `RequestParser` plus the
  domain form/check/schema layers.
  """

  alias EdgeAdmin.Sort
  alias OpenApiSpex.Schema

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
  Sort parameter: `sort`.

  ## Options

    * `:example` — value using `-` for descending fields (default `"-inserted_at"`)
  """
  @spec sort(keyword()) :: keyword()
  def sort(opts \\ []) do
    example = Keyword.get(opts, :example, "-inserted_at")

    [
      sort: [
        in: :query,
        description: "Comma-separated sort fields; prefix a field with - for descending order",
        schema: %Schema{type: :string, pattern: Sort.pattern()},
        example: example
      ]
    ]
  end

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

  Emitted as a string because the REST wire format is comma-separated and this
  keeps Swagger UI clearable for optional query parameters.
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
       schema: %Schema{type: :string}
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

  Emitted as a string because the REST wire format is comma-separated. Enum
  validity is enforced at the OpenApiSpex boundary with a generated pattern.
  """
  @spec enum_in_filter(atom(), [String.t()], keyword()) :: {atom(), keyword()}
  def enum_in_filter(name, values, opts \\ []) when is_atom(name) and is_list(values) do
    key = :"#{name}__in"
    pattern = EdgeAdmin.Naming.enum_in_pattern(values)

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
       schema: %Schema{type: :string, pattern: pattern}
     ]}
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

  Emitted as a string because the REST wire format is comma-separated. Each
  UUID is validated after parsing.
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
       schema: %Schema{type: :string}
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
