# edge_admin/lib/edge_admin_web/plugs/mcp_dedicated_guard.ex
defmodule EdgeAdminWeb.Plugs.McpDedicatedGuard do
  @moduledoc """
  Hides the Phoenix MCP route when MCP is configured on its dedicated port.

  The dedicated listener and the Phoenix endpoint use the same MCP server. This
  plug prevents both listeners from exposing `/mcp` at the same time.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:edge_admin, :admin_mcp_dedicated, false) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not Found")
      |> halt()
    else
      conn
    end
  end
end
