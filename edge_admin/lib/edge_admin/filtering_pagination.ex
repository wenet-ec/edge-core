# edge_admin/lib/edge_admin/filtering_pagination.ex
defmodule EdgeAdmin.FilteringPagination do
  @moduledoc """
  Provides filtering and pagination functionality for Ecto queries.

  This module handles:
  - Query parameter parsing and validation
  - Dynamic filtering based on schema fields
  - Pagination with configurable page sizes
  - Multi-field sorting with individual directions
  - Metadata for API responses

  ## Sort Format

  Supports multiple sort fields with individual directions:
  - Single: `sort=name:asc`
  - Multiple: `sort=status:desc,inserted_at:asc,name:desc`
  - Default direction: `sort=name,status:desc` (name will be :asc)
  """

  import Ecto.Query

  @default_page_size 20
  @max_page_size 100

  defstruct [
    :data,
    :page,
    :page_size,
    :total,
    :total_pages,
    :has_next,
    :has_prev,
    :filters,
    :sort
  ]

  @type sort_item :: {atom(), :asc | :desc}
  @type t :: %__MODULE__{
          data: [any()],
          page: pos_integer(),
          page_size: pos_integer(),
          total: non_neg_integer(),
          total_pages: non_neg_integer(),
          has_next: boolean(),
          has_prev: boolean(),
          filters: map(),
          sort: [sort_item()]
        }

  def paginate(queryable, params \\ %{}, opts \\ []) do
    repo = Keyword.get(opts, :repo, EdgeAdmin.Repo)
    filterable_fields = Keyword.get(opts, :filterable_fields, [])
    sortable_fields = Keyword.get(opts, :sortable_fields, [])
    default_sort = Keyword.get(opts, :default_sort, [])
    default_page_size = Keyword.get(opts, :page_size, @default_page_size)
    max_page_size = Keyword.get(opts, :max_page_size, @max_page_size)

    # Parse and validate parameters
    parsed_params =
      parse_params(params, %{
        filterable_fields: filterable_fields,
        sortable_fields: sortable_fields,
        default_sort: default_sort,
        default_page_size: default_page_size,
        max_page_size: max_page_size
      })

    # Build the query with filters and sorting
    query =
      queryable
      |> apply_filters(parsed_params.filters, filterable_fields)
      |> apply_sorting(parsed_params.sort, sortable_fields)

    # Get total count before applying pagination
    total = get_total_count(query, repo)

    # Calculate pagination metadata
    total_pages = calculate_total_pages(total, parsed_params.page_size)
    has_next = parsed_params.page < total_pages
    has_prev = parsed_params.page > 1

    # Apply pagination and fetch results
    data =
      query
      |> limit(^parsed_params.page_size)
      |> offset(^((parsed_params.page - 1) * parsed_params.page_size))
      |> repo.all()

    %__MODULE__{
      data: data,
      page: parsed_params.page,
      page_size: parsed_params.page_size,
      total: total,
      total_pages: total_pages,
      has_next: has_next,
      has_prev: has_prev,
      filters: parsed_params.filters,
      sort: parsed_params.sort
    }
  end

  # Parse and validate parameters
  defp parse_params(params, opts) do
    %{
      page: parse_page(params["page"]),
      page_size: parse_page_size(params["page_size"], opts.default_page_size, opts.max_page_size),
      filters: parse_filters(params, opts.filterable_fields),
      sort: parse_sort(params["sort"], opts.default_sort, opts.sortable_fields)
    }
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {num, ""} when num > 0 -> num
      _ -> 1
    end
  end

  defp parse_page(page) when is_integer(page) and page > 0, do: page
  defp parse_page(_), do: 1

  defp parse_page_size(nil, default, _max), do: default

  defp parse_page_size(size, default, max) when is_binary(size) do
    case Integer.parse(size) do
      {num, ""} when num > 0 and num <= max -> num
      {num, ""} when num > max -> max
      _ -> default
    end
  end

  defp parse_page_size(size, _default, max) when is_integer(size) and size > 0 and size <= max, do: size

  defp parse_page_size(size, _default, max) when is_integer(size) and size > max, do: max
  defp parse_page_size(_, default, _max), do: default

  defp parse_filters(params, filterable_fields) do
    filterable_field_strings = Enum.map(filterable_fields, &to_string/1)

    params
    |> Map.take(filterable_field_strings)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  def parse_sort(sort_param, default_sort, sortable_fields)

  def parse_sort(nil, default_sort, sortable_fields) do
    normalize_sort(default_sort, sortable_fields)
  end

  def parse_sort(sort_param, _default_sort, sortable_fields) when is_binary(sort_param) do
    sort_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_sort_field/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn {field, _dir} -> field in sortable_fields end)
    |> case do
      [] -> []
      parsed -> parsed
    end
  end

  def parse_sort(_sort_param, default_sort, sortable_fields) do
    normalize_sort(default_sort, sortable_fields)
  end

  defp parse_sort_field(field_spec) do
    case String.split(field_spec, ":") do
      [field] ->
        {String.to_existing_atom(field), :asc}

      [field, "asc"] ->
        {String.to_existing_atom(field), :asc}

      [field, "desc"] ->
        {String.to_existing_atom(field), :desc}

      _ ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  defp normalize_sort(sort, sortable_fields)

  defp normalize_sort(sort, sortable_fields) when is_binary(sort) do
    parse_sort(sort, [], sortable_fields)
  end

  defp normalize_sort(sort, sortable_fields) when is_list(sort) do
    Enum.filter(sort, fn {field, _dir} -> field in sortable_fields end)
  end

  defp normalize_sort(_sort, _sortable_fields), do: []

  defp apply_filters(query, filters, _filterable_fields) when map_size(filters) == 0, do: query

  defp apply_filters(query, filters, filterable_fields) do
    Enum.reduce(filters, query, fn {field_str, value}, acc_query ->
      field = String.to_existing_atom(field_str)

      if field in filterable_fields do
        apply_filter(acc_query, field, value)
      else
        acc_query
      end
    end)
  rescue
    ArgumentError -> query
  end

  defp apply_filter(query, field, value) do
    cond do
      # Handle boolean values
      value in ["true", "false"] ->
        bool_value = value == "true"
        where(query, [q], field(q, ^field) == ^bool_value)

      # Handle nil/null/none values
      value in ["null", "nil", "none"] ->
        where(query, [q], is_nil(field(q, ^field)))

      # Handle "not null" values
      value in ["not_null", "not_nil", "not_none"] ->
        where(query, [q], not is_nil(field(q, ^field)))

      # Handle comma-separated lists (IN operation)
      String.contains?(value, ",") ->
        values = value |> String.split(",") |> Enum.map(&String.trim/1)
        where(query, [q], field(q, ^field) in ^values)

      # Handle range queries (e.g., "gte:100", "lt:50")
      String.contains?(value, ":") ->
        apply_range_filter(query, field, value)

      # Handle wildcard/partial matches
      String.contains?(value, "*") ->
        like_value = String.replace(value, "*", "%")
        where(query, [q], like(field(q, ^field), ^like_value))

      # Default: exact match
      true ->
        where(query, [q], field(q, ^field) == ^value)
    end
  end

  defp apply_range_filter(query, field, value) do
    case String.split(value, ":", parts: 2) do
      ["gte", val] -> where(query, [q], field(q, ^field) >= ^val)
      ["gt", val] -> where(query, [q], field(q, ^field) > ^val)
      ["lte", val] -> where(query, [q], field(q, ^field) <= ^val)
      ["lt", val] -> where(query, [q], field(q, ^field) < ^val)
      ["ne", val] -> where(query, [q], field(q, ^field) != ^val)
      _ -> query
    end
  end

  defp apply_sorting(query, [], _sortable_fields), do: query

  defp apply_sorting(query, sort_list, _sortable_fields) do
    Enum.reduce(sort_list, query, fn {field, direction}, acc_query ->
      order_by(acc_query, [{^direction, ^field}])
    end)
  end

  defp get_total_count(query, repo) do
    # Check if query has GROUP BY (which requires special handling for counts)
    has_group_by = query.group_bys != []

    if has_group_by do
      # For grouped queries (with GROUP BY and potentially HAVING),
      # we need to count the number of groups after grouping/filtering.
      # Wrap the query in a subquery and count the resulting rows.
      subquery =
        query
        |> exclude(:order_by)
        |> exclude(:preload)
        |> subquery()

      from(s in subquery, select: count())
      |> repo.one()
    else
      # For non-grouped queries, use the simple count approach
      query
      |> exclude(:order_by)
      |> exclude(:preload)
      |> exclude(:select)
      |> select([q], count())
      |> repo.one()
    end
  end

  defp calculate_total_pages(0, _page_size), do: 0

  defp calculate_total_pages(total, page_size) do
    (total / page_size) |> Float.ceil() |> trunc()
  end
end
