# edge_admin/lib/edge_admin_web/plugs/metrics_auth.ex
defmodule EdgeAdminWeb.Plugs.MetricsAuth do
  @moduledoc """
  Plug for metrics endpoint authentication.

  Validates that requests include either a master key or metrics key in the Authorization header.
  Can be disabled globally via AUTH_ENABLED=false configuration.

  ## Usage

      plug EdgeAdminWeb.Plugs.MetricsAuth

  ## Authentication

  Accepts either:
  - `Authorization: Bearer <MASTER_KEY>` (omnipotent access)
  - `Authorization: Bearer <METRICS_KEY>` (scoped to metrics endpoints)
  """

  import Phoenix.Controller
  import Plug.Conn

  alias EdgeAdminWeb.ResponseEnvelope

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:edge_admin, :auth_enabled, true) do
      validate_metrics_key(conn)
    else
      # Auth disabled - pass through
      conn
    end
  end

  defp validate_metrics_key(conn) do
    master_key = Application.get_env(:edge_admin, :master_key)
    metrics_key = Application.get_env(:edge_admin, :metrics_key)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> ^master_key] ->
        # Master key works (omnipotent)
        conn

      ["Bearer " <> ^metrics_key] ->
        # Metrics key works (scoped)
        conn

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(ResponseEnvelope.error(conn, "unauthorized", "Unauthorized"))
        |> halt()
    end
  end
end
