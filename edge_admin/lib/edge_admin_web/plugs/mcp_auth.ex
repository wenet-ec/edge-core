# edge_admin/lib/edge_admin_web/plugs/mcp_auth.ex
defmodule EdgeAdminWeb.Plugs.McpAuth do
  @moduledoc """
  Plug for MCP endpoint authentication.

  Validates that requests include either a master key or MCP key in the Authorization header.
  Can be disabled globally via AUTH_ENABLED=false configuration.

  ## Usage

      plug EdgeAdminWeb.Plugs.McpAuth

  ## Authentication

  Accepts either:
  - `Authorization: Bearer <MASTER_KEY>` (omnipotent fallback)
  - `Authorization: Bearer <MCP_KEY>` (scoped to MCP endpoint)

  MCP_KEY defaults to MASTER_KEY if unset.
  """

  import Phoenix.Controller
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:edge_admin, :auth_enabled, true) do
      validate_mcp_key(conn)
    else
      conn
    end
  end

  defp validate_mcp_key(conn) do
    master_key = Application.get_env(:edge_admin, :master_key)
    mcp_key = Application.get_env(:edge_admin, :mcp_key)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> ^master_key] ->
        conn

      ["Bearer " <> ^mcp_key] ->
        conn

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end
