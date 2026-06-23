# edge_admin/lib/edge_admin_mcp/flop_params.ex
defmodule EdgeAdminMcp.FlopParams do
  @moduledoc """
  Translates atom-keyed MCP tool params into the string-keyed map that
  `EdgeAdmin.RequestParser.parse/1` expects.

  MCP tool schemas use single-underscore suffixes (`inserted_at_gte`,
  `status_in`, `node_id_in`). `RequestParser` expects double-underscore
  Flop operators (`inserted_at__gte`, `status__in`, `node_id__in`).

  `build/1` scans every param key automatically by pattern — no per-tool
  `passthrough:` / `multi:` / `ranges:` declarations needed.

  ## Translation rules (applied to every non-nil param)

  | MCP key pattern      | value type | emits                            |
  |----------------------|------------|----------------------------------|
  | `<field>_in`         | list       | `"<field>__in" => "a,b,c"`       |
  | `<field>_gte`        | any        | `"<field>__gte" => value`        |
  | `<field>_lte`        | any        | `"<field>__lte" => value`        |
  | `<field>`            | boolean    | `"<field>" => true/false`        |
  | `<field>`            | string/int | `"<field>" => value`             |
  | `page` / `page_size` | integer    | `"page"` / `"page_size"` (reserved) |
  | `order_by` / `order_directions` | string | passed through as-is  |

  Nil values are always dropped. Reserved keys (`page`, `page_size`,
  `order_by`, `order_directions`) are handled separately and not treated
  as filter fields.
  """

  # event_type is a post-filter injected by list_webhooks after build/1 — skip it here
  @reserved ~w(page page_size order_by order_directions event_type)a

  @default_page 1
  @default_page_size 20

  @doc """
  Translate MCP atom-keyed params into a `RequestParser`-compatible string map.

  Accepts an optional `default_page_size:` keyword.
  """
  @spec build(map(), keyword()) :: map()
  def build(params, opts \\ []) do
    default_page_size = Keyword.get(opts, :default_page_size, @default_page_size)

    base = %{
      "page" => params[:page] || @default_page,
      "page_size" => params[:page_size] || default_page_size
    }

    base
    |> add_sort(params)
    |> add_filters(params)
  end

  defp add_sort(query, params) do
    query
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end

  defp add_filters(query, params) do
    Enum.reduce(params, query, fn {key, value}, acc ->
      if key in @reserved or is_nil(value) do
        acc
      else
        translate(acc, key, value)
      end
    end)
  end

  # <field>_in list → "<field>__in" comma-joined string
  defp translate(acc, key, value) when is_list(value) and value != [] do
    str = Atom.to_string(key)

    if String.ends_with?(str, "_in") do
      field = String.slice(str, 0, byte_size(str) - 3)
      Map.put(acc, "#{field}__in", Enum.join(value, ","))
    else
      acc
    end
  end

  # <field>_gte / <field>_lte → double-underscore
  defp translate(acc, key, value) do
    str = Atom.to_string(key)

    cond do
      String.ends_with?(str, "_gte") ->
        field = String.slice(str, 0, byte_size(str) - 4)
        put_if(acc, "#{field}__gte", value)

      String.ends_with?(str, "_lte") ->
        field = String.slice(str, 0, byte_size(str) - 4)
        put_if(acc, "#{field}__lte", value)

      true ->
        put_if(acc, str, value)
    end
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
