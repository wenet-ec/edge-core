# edge_admin/lib/edge_admin_web/plugs/master_key_auth.ex
defmodule EdgeAdminWeb.Plugs.MasterKeyAuth do
  @moduledoc """
  Plug for master key authentication.

  Validates that requests include a valid master key in the Authorization header.
  Can be disabled globally via AUTH_ENABLED=false configuration.

  ## Usage

      plug EdgeAdminWeb.Plugs.MasterKeyAuth

  ## Authentication

  Requires `Authorization: Bearer <MASTER_KEY>` header.
  """

  import Phoenix.Controller
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:edge_admin, :auth_enabled, true) do
      validate_master_key(conn)
    else
      # Auth disabled - pass through
      conn
    end
  end

  defp validate_master_key(conn) do
    master_key = Application.get_env(:edge_admin, :master_key)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> ^master_key] ->
        conn

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unauthorized"})
        |> halt()
    end
  end
end
