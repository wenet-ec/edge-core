# edge_agent/lib/edge_agent_web/controllers/diagnostics_json.ex
defmodule EdgeAgentWeb.Controllers.DiagnosticsJSON do
  alias EdgeAgentWeb.ResponseEnvelope

  def show(%{conn: conn, diagnostic: diagnostic}) do
    ResponseEnvelope.success(conn, diagnostic)
  end
end
