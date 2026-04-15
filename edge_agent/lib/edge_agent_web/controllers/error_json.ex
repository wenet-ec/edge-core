# edge_agent/lib/edge_agent_web/controllers/error_json.ex
defmodule EdgeAgentWeb.Controllers.ErrorJSON do
  alias EdgeAgentWeb.ResponseEnvelope

  def render("400.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "bad_request", "Malformed request body")
  end

  def render("401.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "unauthorized", "Missing or invalid credentials")
  end

  def render("403.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "forbidden", "Insufficient permissions")
  end

  def render("404.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "not_found", "Resource not found")
  end

  def render("409.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "conflict", "Resource already exists")
  end

  def render("503.json", %{conn: conn}) do
    ResponseEnvelope.error(conn, "service_unavailable", "Downstream dependency unreachable")
  end

  def render(_, %{conn: conn}) do
    ResponseEnvelope.error(conn, "internal_server_error", "An unexpected error occurred")
  end
end
