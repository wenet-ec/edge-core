# edge_agent/lib/edge_agent_web/controllers/diagnostics_controller.ex
defmodule EdgeAgentWeb.Controllers.DiagnosticsController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.Diagnostics

  @doc """
  Runs read-only Agent diagnostics for an authenticated Admin.
  """
  def show(conn, _params) do
    render(conn, :show, conn: conn, diagnostic: Diagnostics.run())
  end
end
