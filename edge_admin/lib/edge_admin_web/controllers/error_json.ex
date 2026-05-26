# edge_admin/lib/edge_admin_web/controllers/error_json.ex
defmodule EdgeAdminWeb.Controllers.ErrorJSON do
  @moduledoc """
  Renders standard error envelopes for HTTP error responses.
  All output goes through ResponseEnvelope — no ad-hoc maps here.
  """

  alias EdgeAdminWeb.ResponseEnvelope

  def render("400.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "bad_request", "Bad Request")
  end

  def render("401.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "unauthorized", "Unauthorized")
  end

  def render("403.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "forbidden", "Forbidden")
  end

  def render("404.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "not_found", "Resource not found")
  end

  def render("409.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "conflict", "Conflict")
  end

  def render("500.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "internal_server_error", "Internal Server Error")
  end

  def render("503.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "service_unavailable", "Service Unavailable")
  end

  # Distinct from `503.json` — rendered by `Plugs.DegradedMode` when the admin
  # cluster is over capacity. Same wire status (503) but a more specific code +
  # message so clients can distinguish "wait briefly" (downstream dep flapping)
  # from "you exceeded capacity, fix that". MCP renders the same vocabulary
  # via `EdgeAdminMcp.ToolError.message(:degraded_mode)`.
  def render("503_degraded_mode.json", %{conn: conn}) do
    ResponseEnvelope.error(
      conn,
      "degraded_mode",
      "Cluster is in degraded mode (over capacity) — try again when capacity recovers"
    )
  end

  def render(_, %{conn: conn}) do
    ResponseEnvelope.error(conn, "internal_server_error", "An unexpected error occurred")
  end
end
