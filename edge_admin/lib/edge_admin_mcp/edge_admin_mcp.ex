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
  - `error_response/1` — renders a known reason via `EdgeAdminMcp.ToolError.message/1`
  - `error_response/2` — renders a custom message for any error code
  - `put_if/3` — adds a key to a map only when the value is non-nil. Use on
    *create* paths where `nil` means "the user didn't pass this field."
  - `put_if_present/4` — adds a key to a map iff the source key was *present*
    in `params`, even if its value is `nil`. Use on *update* paths where the
    user can pass `null` to mean "clear this field," distinct from omitting
    it (which means "leave unchanged"). Peri preserves explicit nulls
    through validation, so `Map.has_key?/2` correctly distinguishes the two.

  See `EdgeAdminMcp.ToolError` for the full error code table.

  Context aliases (Nodes, Commands, Ssh, etc.) are still aliased
  per file since each tool file belongs to one context.
  """

  alias Anubis.Server.Response

  def tool do
    quote do
      use Anubis.Server.Component, type: :tool

      alias Anubis.Server.Response

      defp paginated(items, meta, mapper \\ & &1), do: EdgeAdminMcp.paginated(items, meta, mapper)
      defp error_response(reason), do: EdgeAdminMcp.error_response(reason)
      defp error_response(code, msg), do: EdgeAdminMcp.error_response(code, msg)
      defp put_if(m, _k, nil), do: m
      defp put_if(m, k, v), do: Map.put(m, k, v)

      defp put_if_present(attrs, attr_key, params, param_key) do
        if Map.has_key?(params, param_key) do
          Map.put(attrs, attr_key, params[param_key])
        else
          attrs
        end
      end
    end
  end

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
  def error_response(reason) do
    Response.error(Response.tool(), EdgeAdminMcp.ToolError.message(reason))
  end

  @doc """
  Renders an MCP tool error response with a custom message.

  Used when the tool wants a more informative message than the default
  `ToolError.message/1` would produce (e.g. including the resource id):

      error_response(:not_found, "Command \#{id} not found")

  The `code` is currently informational — it is not surfaced to the client
  in the response body, but tools should still pass an honest code so the
  intent is clear at the call site.
  """
  def error_response(_code, msg) when is_binary(msg) do
    Response.error(Response.tool(), msg)
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
