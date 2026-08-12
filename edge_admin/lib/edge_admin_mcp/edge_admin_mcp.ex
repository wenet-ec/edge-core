# edge_admin/lib/edge_admin_mcp/edge_admin_mcp.ex
defmodule EdgeAdminMcp do
  @moduledoc """
  Entrypoint for MCP tool definitions.

  `use EdgeAdminMcp, :tool` injects:
  - `use Anubis.Server.Component, type: :tool`
  - `alias Anubis.Server.Response`
  - `input_schema/0` override — rewrites the Peri JSON Schema into
    inspector-friendly form before it is served to MCP clients (see
    `normalize_json_schema/1` for the rewrite rules).
  - `paginated/3` — builds the standard MCP list response shape
  - `error_response/1` — renders a known reason via `EdgeAdminMcp.ToolError.message/1`
  - `error_response/2` — renders a custom message for any error code
  - `put_if/3` — delegates to `EdgeAdminMcp.put_if/3`. Adds a key to a map
    only when the value is non-nil. Use on *create* paths where `nil` means
    "the user didn't pass this field."
  - `put_if_present/4` — delegates to `EdgeAdminMcp.put_if_present/4`. Adds
    a key to a map iff the source key was *present* in `params`, even if its
    value is `nil`. Use on *update* paths where the user can pass `null` to
    mean "clear this field," distinct from omitting it (which means "leave
    unchanged"). Peri preserves explicit nulls through validation, so
    `Map.has_key?/2` correctly distinguishes the two.

  See `EdgeAdminMcp.ToolError` for the full error code table.

  Context aliases (Nodes, Commands, Ssh, etc.) are still aliased
  per file since each tool file belongs to one context.
  """

  alias Anubis.Server.Response

  @doc "Returns the `use EdgeAdminMcp, :tool` expansion used by MCP tool modules."
  def tool do
    quote do
      use Anubis.Server.Component, type: :tool

      alias Anubis.Server.Response

      defoverridable input_schema: 0

      def input_schema do
        EdgeAdminMcp.normalize_json_schema(super())
      end

      defp paginated(items, meta, mapper \\ & &1), do: EdgeAdminMcp.paginated(items, meta, mapper)
      defp error_response(reason), do: EdgeAdminMcp.error_response(reason)
      defp error_response(code, msg), do: EdgeAdminMcp.error_response(code, msg)
      defp put_if(m, k, v), do: EdgeAdminMcp.put_if(m, k, v)
      defp put_if_present(attrs, key, params, param_key), do: EdgeAdminMcp.put_if_present(attrs, key, params, param_key)
    end
  end

  @doc """
  Recursively rewrites a Peri JSON Schema into a form the MCP
  inspector's `DynamicJsonForm` can render.

  Peri emits certain `oneOf` unions that have no top-level `type`, which the
  inspector treats as unrenderable and silently skips. Two cases are fixed:

  - **Nullable boolean** — `oneOf: [bool, null]` → `anyOf: [bool, null]`
    so MCP clients can render nullable boolean inputs consistently.

  - **String-or-array** — `oneOf: [string, array]` → `type: string`
    The inspector has no mixed-type control. A comma-separated string covers
    the common case and the runtime `RequestParser` accepts it. Callers who
    need to pass a list use JSON mode.
  """
  @spec normalize_json_schema(map()) :: map()
  def normalize_json_schema(schema) when is_map(schema) do
    rewrite_unions(schema)
  end

  defp rewrite_unions(%{"oneOf" => branches} = schema) when is_list(branches) do
    cond do
      nullable_boolean_union?(branches) ->
        schema |> Map.delete("oneOf") |> Map.put("anyOf", branches)

      string_or_array_union?(branches) ->
        schema |> Map.delete("oneOf") |> Map.put("type", "string")

      true ->
        Map.update!(schema, "oneOf", fn bs -> Enum.map(bs, &rewrite_unions/1) end)
    end
  end

  defp rewrite_unions(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) -> {k, rewrite_unions(v)}
      {k, v} when is_list(v) -> {k, Enum.map(v, &rewrite_unions/1)}
      pair -> pair
    end)
  end

  defp rewrite_unions(value), do: value

  defp nullable_boolean_union?(branches) do
    Enum.any?(branches, &(&1 == %{"type" => "boolean"})) and
      Enum.any?(branches, &(&1 == %{"type" => "null"}))
  end

  defp string_or_array_union?(branches) do
    Enum.any?(branches, &(&1 == %{"type" => "string"})) and
      Enum.any?(branches, &(is_map(&1) and Map.get(&1, "type") == "array"))
  end

  @doc "Builds the standard paginated response payload used by MCP list tools."
  @spec paginated(list(), map(), (term() -> term())) :: map()
  def paginated(items, meta, mapper \\ & &1) do
    %{
      items: Enum.map(items, mapper),
      page: meta.current_page,
      page_size: meta.page_size,
      total_count: meta.total_count,
      total_pages: meta.total_pages,
      has_next: meta.has_next_page?,
      has_prev: meta.has_previous_page?
    }
  end

  @doc """
  Renders a known error reason as an MCP tool error response.

  The `reason` is passed through `EdgeAdminMcp.ToolError.message/1` to produce
  a human-readable string (`%Ecto.Changeset{}`, `:not_found`, etc.).
  """
  @spec error_response(term()) :: term()
  def error_response(reason) do
    Response.error(Response.tool(), EdgeAdminMcp.ToolError.message(reason))
  end

  @doc """
  Renders an MCP tool error response with a custom message.

  Used when the tool wants a more informative message than the default
  `ToolError.message/1` would produce, such as including the resource id.

  The `code` is currently informational — it is not surfaced to the client
  in the response body, but tools should still pass an honest code so the
  intent is clear at the call site.
  """
  @spec error_response(term(), String.t()) :: term()
  def error_response(_code, msg) when is_binary(msg) do
    Response.error(Response.tool(), msg)
  end

  @doc "Adds a map entry unless its value is nil."
  @spec put_if(map(), term(), term()) :: map()
  def put_if(m, _k, nil), do: m
  def put_if(m, k, v), do: Map.put(m, k, v)

  @doc "Adds an entry when the source map contains the requested key, including nil values."
  @spec put_if_present(map(), term(), map(), term()) :: map()
  def put_if_present(attrs, attr_key, params, param_key) do
    if Map.has_key?(params, param_key) do
      Map.put(attrs, attr_key, params[param_key])
    else
      attrs
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
