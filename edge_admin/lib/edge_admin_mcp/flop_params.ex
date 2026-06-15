# edge_admin/lib/edge_admin_mcp/flop_params.ex
defmodule EdgeAdminMcp.FlopParams do
  @moduledoc """
  Builds the Flop-shaped query map from MCP tool params.

  MCP tool schemas use snake_case keys with single underscores
  (`inserted_at_gte`, `timeout_lte`). Flop expects double-underscore
  separators on range filters (`inserted_at__gte`, `timeout__lte`).

  This helper takes the params map plus a small spec describing each
  filter and produces the right shape, with pagination + sort included.

  ## Usage

      build(params,
        passthrough: [:status, :name, :cluster_name, :has_password],
        ranges: [:inserted_at, :updated_at, :timeout]
      )

  The `:passthrough` keys are passed through unchanged (atom → string key).
  The `:ranges` keys expand to two filters each — `<key>_gte` → `<key>__gte`,
  `<key>_lte` → `<key>__lte`. Nil values are dropped.

  Pagination (`page`, `page_size`) and sort (`order_by`, `order_directions`)
  are always included.
  """

  @default_page 1
  @default_page_size 20

  @doc """
  Build a Flop-shaped string-keyed query map from MCP tool params.

  ## Options

    * `:passthrough` — list of atom keys copied as-is to string keys.
    * `:multi` — list of atom keys that are `{:array, :string}` in the MCP
      schema. The list value is joined to a comma-separated string so
      `RequestParser` picks it up as an `op: :in` filter (same wire format as
      the REST comma-separated convention).
    * `:ranges` — list of atom field names expanded into `<field>_gte` /
      `<field>_lte` (renamed to Flop's `<field>__gte` / `<field>__lte`).
    * `:default_page_size` — overrides the default of 20.
  """
  @spec build(map() | keyword(), keyword()) :: map()
  def build(params, opts \\ []) do
    passthrough = Keyword.get(opts, :passthrough, [])
    multi = Keyword.get(opts, :multi, [])
    ranges = Keyword.get(opts, :ranges, [])
    default_page_size = Keyword.get(opts, :default_page_size, @default_page_size)

    base = %{
      "page" => params[:page] || @default_page,
      "page_size" => params[:page_size] || default_page_size
    }

    base
    |> add_passthrough(params, passthrough)
    |> add_multi(params, multi)
    |> add_ranges(params, ranges)
    |> add_sort(params)
  end

  defp add_passthrough(query, params, fields) do
    Enum.reduce(fields, query, fn field, acc ->
      put_if(acc, Atom.to_string(field), params[field])
    end)
  end

  defp add_multi(query, params, fields) do
    Enum.reduce(fields, query, fn field, acc ->
      case params[field] do
        values when is_list(values) and values != [] ->
          Map.put(acc, Atom.to_string(field), Enum.join(values, ","))

        _ ->
          acc
      end
    end)
  end

  defp add_ranges(query, params, fields) do
    Enum.reduce(fields, query, fn field, acc ->
      base = Atom.to_string(field)
      gte_atom = :"#{base}_gte"
      lte_atom = :"#{base}_lte"

      acc
      |> put_if("#{base}__gte", params[gte_atom])
      |> put_if("#{base}__lte", params[lte_atom])
    end)
  end

  defp add_sort(query, params) do
    query
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
