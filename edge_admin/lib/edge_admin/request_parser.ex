# edge_admin/lib/edge_admin/request_parser.ex
defmodule EdgeAdmin.RequestParser do
  @moduledoc """
  Parses flat query params from API requests into Flop-compatible format.

  Converts URL query strings like:
    ?name=prod*&inserted_at__gte=2025-01-01&order_by=inserted_at&order_directions=desc

  Into Flop params:
    %{
      filters: [
        %{field: :name, op: :ilike, value: "prod%"},
        %{field: :inserted_at, op: :>=, value: "2025-01-01T00:00:00Z"}
      ],
      order_by: [:inserted_at],
      order_directions: [:desc],
      page: 1,
      page_size: 20
    }

  ## Supported Operators

  ### Text Search
  - `field=value` - Exact match
  - `field=*value` - Ends with (ilike)
  - `field=value*` - Starts with (ilike)
  - `field=*value*` - Contains (ilike)

  ### Range/Comparison
  - `field__gte=value` - Greater than or equal (>=)
  - `field__gt=value` - Greater than (>)
  - `field__lte=value` - Less than or equal (<=)
  - `field__lt=value` - Less than (<)
  - `field__ne=value` - Not equal (!=)

  ### Null checks
  - `field__null=true` - Field is null (:empty)
  - `field__null=false` - Field is not null (:not_empty)

  ### Other
  - `field=true/false` - Boolean exact match
  - `field=value1,value2` - IN operator
  - `field__in=value1,value2` - Explicit IN operator

  ### Pagination & Sorting
  - `page=1` - Page number (default: 1)
  - `page_size=20` - Items per page (default: 20, max: 100)
  - `order_by=field1,field2` - Fields to sort by
  - `order_directions=desc,asc` - Sort directions (default: asc for each field)
  """

  @default_page_size 20
  @max_page_size 100

  # Reserved params that aren't filters
  @reserved_params ~w(page page_size order_by order_directions sort_by sort_order)

  @doc """
  Parses flat query params into Flop format.

  ## Examples

      iex> parse(%{"name" => "prod*", "page" => "1"})
      %{
        filters: [%{field: :name, op: :ilike, value: "prod%"}],
        page: 1,
        page_size: 20
      }

      iex> parse(%{"inserted_at__gte" => "2025-01-01", "status" => "active"})
      %{
        filters: [
          %{field: :inserted_at, op: :>=, value: "2025-01-01T00:00:00Z"},
          %{field: :status, op: :==, value: "active"}
        ],
        page: 1,
        page_size: 20
      }
  """
  def parse(params) when is_map(params) do
    compact(%{
      filters: parse_filters(params),
      page: parse_page(params),
      page_size: parse_page_size(params),
      order_by: parse_order_by(params),
      order_directions: parse_order_directions(params)
    })
  end

  @doc """
  Splits ilike filters for the given fields out of a Flop params map.

  Flop's `:ilike` operator calls `add_wildcard/1` internally, which escapes any
  `%` characters in the value and wraps the whole thing in `%..%`. This breaks
  user-supplied wildcard patterns like `"prod%"` (starts-with) because the `%`
  gets escaped before the SQL executes.

  Call this after `parse/1` to extract ilike filters for fields you want to
  apply as raw Ecto `ilike/2` clauses instead of letting Flop handle them.

  ## Returns
  `{ilike_filters, updated_flop_params}` where `ilike_filters` is a list of
  `%{field: atom, op: :ilike, value: binary}` maps and `updated_flop_params`
  has those filters removed.

  ## Example

      flop_params = RequestParser.parse(params)
      {ilike_filters, flop_params} = RequestParser.split_ilike_filters(flop_params, [:name, :version])
      query = Enum.reduce(ilike_filters, base_query, fn %{field: f, value: v}, q ->
        from(r in q, where: ilike(field(r, ^f), ^v))
      end)
  """
  def split_ilike_filters(flop_params, fields) when is_list(fields) do
    {ilike, other} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.op == :ilike and filter.field in fields
      end)

    {ilike, Map.put(flop_params, :filters, other)}
  end

  # Parse filters from params
  defp parse_filters(params) do
    params
    |> Enum.reject(fn {key, _value} -> key in @reserved_params end)
    |> Enum.flat_map(fn {key, value} -> parse_filter(key, value) end)
    |> Enum.reject(&is_nil/1)
  end

  # When CastAndValidate is active, boolean params arrive as actual booleans.
  defp parse_filter(key, value) when is_binary(key) and is_boolean(value) do
    case parse_field(key) do
      {:ok, field} -> [%{field: field, op: :==, value: value}]
      _ -> []
    end
  end

  # When CastAndValidate is active, integer params (node_count__gte etc.) arrive as integers.
  defp parse_filter(key, value) when is_binary(key) and is_integer(value) do
    if String.contains?(key, "__") do
      case String.split(key, "__", parts: 2) do
        [field_str, op_str] ->
          with {:ok, field} <- parse_field(field_str),
               {:ok, op} <- parse_operator(op_str) do
            [%{field: field, op: op, value: value}]
          else
            _ -> []
          end

        _ ->
          []
      end
    else
      case parse_field(key) do
        {:ok, field} -> [%{field: field, op: :==, value: value}]
        _ -> []
      end
    end
  end

  # When CastAndValidate is active, anyOf date/datetime params arrive as %Date{} or %DateTime{} structs.
  defp parse_filter(key, %Date{} = value) when is_binary(key) do
    parse_filter(key, Date.to_iso8601(value))
  end

  defp parse_filter(key, %DateTime{} = value) when is_binary(key) do
    parse_filter(key, DateTime.to_iso8601(value))
  end

  # Parse a single filter parameter
  defp parse_filter(key, value) when is_binary(key) and is_binary(value) do
    # Range operators: field__gte, field__lte, etc.
    if String.contains?(key, "__") do
      case String.split(key, "__", parts: 2) do
        [field_str, op_str] ->
          with {:ok, field} <- parse_field(field_str),
               {:ok, op} <- parse_operator(op_str) do
            [build_filter(field, op, value, op_str)]
          else
            _ -> []
          end

        _ ->
          []
      end
    else
      # Regular field filters
      case parse_field(key) do
        {:ok, field} -> parse_value_filter(field, value)
        _ -> []
      end
    end
  end

  defp parse_filter(_key, _value), do: []

  # Build a filter, applying any value coercions needed for the operator
  defp build_filter(field, :null, "false", _op_str) do
    %{field: field, op: :not_empty, value: true}
  end

  defp build_filter(field, :null, _value, _op_str) do
    %{field: field, op: :empty, value: true}
  end

  defp build_filter(field, op, value, op_str) when op_str in ~w(gte gt) do
    %{field: field, op: op, value: maybe_expand_date(value, "T00:00:00Z")}
  end

  defp build_filter(field, op, value, op_str) when op_str in ~w(lte lt) do
    %{field: field, op: op, value: maybe_expand_date(value, "T23:59:59Z")}
  end

  defp build_filter(field, op, value, _op_str) do
    %{field: field, op: op, value: value}
  end

  # Expands a date-only string (YYYY-MM-DD) to a full UTC datetime by appending
  # the given suffix. Full datetime strings are passed through unchanged.
  defp maybe_expand_date(value, suffix) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value), do: value <> suffix, else: value
  end

  # Parse filter based on value pattern
  defp parse_value_filter(field, value) do
    cond do
      # Boolean values
      value in ["true", "false"] ->
        [%{field: field, op: :==, value: value == "true"}]

      # Comma-separated list (IN operator)
      String.contains?(value, ",") ->
        values = value |> String.split(",") |> Enum.map(&String.trim/1)
        [%{field: field, op: :in, value: values}]

      # Wildcard patterns (ilike)
      String.contains?(value, "*") ->
        like_value = String.replace(value, "*", "%")
        [%{field: field, op: :ilike, value: like_value}]

      # Exact match
      true ->
        [%{field: field, op: :==, value: value}]
    end
  end

  # Parse field name to atom
  defp parse_field(field_str) when is_binary(field_str) do
    {:ok, String.to_existing_atom(field_str)}
  rescue
    ArgumentError -> {:error, :invalid_field}
  end

  # Parse operator string to Flop operator
  defp parse_operator("gte"), do: {:ok, :>=}
  defp parse_operator("gt"), do: {:ok, :>}
  defp parse_operator("lte"), do: {:ok, :<=}
  defp parse_operator("lt"), do: {:ok, :<}
  defp parse_operator("ne"), do: {:ok, :!=}
  defp parse_operator("eq"), do: {:ok, :==}
  defp parse_operator("in"), do: {:ok, :in}
  defp parse_operator("ilike"), do: {:ok, :ilike}
  defp parse_operator("like"), do: {:ok, :like}
  defp parse_operator("null"), do: {:ok, :null}
  defp parse_operator(_), do: {:error, :invalid_operator}

  # Parse page number
  # When CastAndValidate is active, page arrives as an integer (already validated >= 1).
  # Without it (agent/internal endpoints), fall back to string parsing.
  defp parse_page(%{"page" => page}) when is_integer(page) and page > 0, do: page

  defp parse_page(%{"page" => page}) when is_binary(page) do
    case Integer.parse(page) do
      {num, ""} when num > 0 -> num
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  # Parse page size
  # When CastAndValidate is active, page_size arrives as an integer (already validated 1..100).
  # Without it, apply clamping manually.
  defp parse_page_size(%{"page_size" => size}) when is_integer(size) and size > 0 and size <= @max_page_size do
    size
  end

  defp parse_page_size(%{"page_size" => size}) when is_integer(size) and size > @max_page_size do
    @max_page_size
  end

  defp parse_page_size(%{"page_size" => size}) when is_binary(size) do
    case Integer.parse(size) do
      {num, ""} when num > 0 and num <= @max_page_size -> num
      {num, ""} when num > @max_page_size -> @max_page_size
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size

  # Parse order_by fields
  defp parse_order_by(%{"order_by" => order_by}) when is_binary(order_by) do
    order_by
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_field/1)
    |> Enum.flat_map(fn
      {:ok, field} -> [field]
      _ -> []
    end)
  end

  defp parse_order_by(_), do: nil

  # Parse order_directions
  defp parse_order_directions(%{"order_directions" => directions}) when is_binary(directions) do
    directions
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_direction/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_order_directions(_), do: nil

  # Parse direction string
  defp parse_direction("asc"), do: :asc
  defp parse_direction("desc"), do: :desc
  defp parse_direction(_), do: nil

  # Remove nil/empty values from map
  defp compact(map) do
    map
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, []} -> true
      _ -> false
    end)
    |> Map.new()
  end
end
