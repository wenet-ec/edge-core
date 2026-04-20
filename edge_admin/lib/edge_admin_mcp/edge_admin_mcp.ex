# edge_admin/lib/edge_admin_mcp/edge_admin_mcp.ex
defmodule EdgeAdminMcp do
  @moduledoc """
  Entrypoint for MCP tool definitions.

  Use this in tool modules to avoid repeating boilerplate:

      use EdgeAdminMcp, :tool

  Injects:
  - `use Anubis.Server.Component, type: :tool`
  - `alias Anubis.Server.Response`
  - `paginated/3` — builds the standard MCP list response shape
  - `error_response/1,2` — builds an MCP error response with `isError: true`
  - `tool_error/1,2` — builds structured error map (use when you need the map directly)
  - `put_if/3` — conditionally adds a key to a map (nil → no-op)

  See `EdgeAdminMcp.ToolError` for the full error code table.

  Context aliases (Nodes, Commands, Ssh, etc.) are still aliased
  per file since each tool file belongs to one context.
  """

  alias Anubis.Server.Response

  def tool do
    quote do
      use Anubis.Server.Component, type: :tool

      alias Anubis.Server.Response

      defp paginated(items, meta, mapper), do: EdgeAdminMcp.paginated(items, meta, mapper)
      defp error_response(reason), do: EdgeAdminMcp.error_response(reason)
      defp error_response(code, msg), do: EdgeAdminMcp.error_response(code, msg)
      defp tool_error(reason), do: EdgeAdminMcp.ToolError.build(reason)
      defp tool_error(code, msg), do: EdgeAdminMcp.ToolError.build(code, msg)
      defp put_if(m, _k, nil), do: m
      defp put_if(m, k, v), do: Map.put(m, k, v)
    end
  end

  def paginated(items, meta, mapper) do
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

  def error_response(reason) do
    Response.error(Response.tool(), EdgeAdminMcp.ToolError.message(reason))
  end

  def error_response(:not_found, msg) when is_binary(msg) do
    Response.error(Response.tool(), msg)
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
