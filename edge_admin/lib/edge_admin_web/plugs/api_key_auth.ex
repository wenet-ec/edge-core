# edge_admin/lib/edge_admin_web/plugs/api_key_auth.ex
defmodule EdgeAdminWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Plug for REST API authentication.

  Validates that requests include either a master key or API key in the Authorization header.
  Can be disabled globally via AUTH_ENABLED=false configuration.

  ## Usage

      plug EdgeAdminWeb.Plugs.ApiKeyAuth

  ## Authentication

  Accepts either:
  - `Authorization: Bearer <MASTER_KEY>` (omnipotent fallback)
  - `Authorization: Bearer <API_KEY>` (scoped to REST API endpoints)
  """

  import Phoenix.Controller
  import Plug.Conn

  alias EdgeAdminWeb.ResponseEnvelope

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:edge_admin, :auth_enabled, true) do
      validate_api_key(conn)
    else
      conn
    end
  end

  defp validate_api_key(conn) do
    master_key = Application.get_env(:edge_admin, :master_key)
    api_key = Application.get_env(:edge_admin, :api_key)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> ^master_key] ->
        conn

      ["Bearer " <> ^api_key] ->
        conn

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(ResponseEnvelope.error(conn, "unauthorized", "Unauthorized"))
        |> halt()
    end
  end
end
