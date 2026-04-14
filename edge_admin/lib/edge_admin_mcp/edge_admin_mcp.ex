# edge_admin/lib/edge_admin_mcp/edge_admin_mcp.ex
defmodule EdgeAdminMcp do
  @moduledoc """
  Entrypoint for MCP tool definitions.

  Use this in tool modules to avoid repeating boilerplate:

      use EdgeAdminMcp, :tool

  Injects:
  - `use Anubis.Server.Component, type: :tool`
  - `alias Anubis.Server.Response`

  Context aliases (Nodes, Commands, Ssh, etc.) are still aliased
  per file since each tool file belongs to one context.
  """

  def tool do
    quote do
      use Anubis.Server.Component, type: :tool

      alias Anubis.Server.Response
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
