# edge_agent/lib/edge_agent_web/controllers/error_json.ex
defmodule EdgeAgentWeb.Controllers.ErrorJSON do
  alias EdgeAgentWeb.ResponseEnvelope

  @error_templates %{
    "400" => {"bad_request", "Malformed request body"},
    "401" => {"unauthorized", "Missing or invalid credentials"},
    "403" => {"forbidden", "Insufficient permissions"},
    "404" => {"not_found", "Resource not found"},
    "409" => {"conflict", "Resource already exists"},
    "500" => {"internal_server_error", "An unexpected error occurred"},
    "503" => {"service_unavailable", "Downstream dependency unreachable"}
  }

  def render(template, %{conn: conn}) do
    {code, message} =
      Map.get(@error_templates, template, {"internal_server_error", "An unexpected error occurred"})

    ResponseEnvelope.error(conn, code, message)
  end
end
