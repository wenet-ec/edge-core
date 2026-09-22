# edge_agent/lib/edge_agent_web/controllers/ingress_tunneling_controller.ex
defmodule EdgeAgentWeb.Controllers.IngressTunnelingController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.IngressTunneling

  action_fallback(EdgeAgentWeb.Controllers.FallbackController)

  def create(conn, params) do
    with {:ok, ingress_tunneling} <- IngressTunneling.upsert_ingress_tunneling(params) do
      render(conn, :show, conn: conn, ingress_tunneling: ingress_tunneling)
    end
  end
end
