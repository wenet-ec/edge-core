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
  - `tool_error/1` — delegates to `EdgeAdminMcp.ToolError.build/1`
  - `tool_error/2` — delegates to `EdgeAdminMcp.ToolError.build/2` (not_found with resource name)
  - `put_if/3` — conditionally adds a key to a map (nil → no-op)

  See `EdgeAdminMcp.ToolError` for the full error code table.

  Context aliases (Nodes, Commands, Ssh, etc.) are still aliased
  per file since each tool file belongs to one context.
  """

  def tool do
    quote do
      use Anubis.Server.Component, type: :tool

      alias Anubis.Server.Response

      defp paginated(items, meta, mapper) do
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

      defp tool_error(reason), do: EdgeAdminMcp.ToolError.build(reason)
      defp tool_error(code, message), do: EdgeAdminMcp.ToolError.build(code, message)

      defp put_if(m, _k, nil), do: m
      defp put_if(m, k, v), do: Map.put(m, k, v)
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
