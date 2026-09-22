# edge_agent/lib/edge_agent_web/controllers/ingress_tunneling_json.ex
defmodule EdgeAgentWeb.Controllers.IngressTunnelingJSON do
  alias EdgeAgentWeb.ResponseEnvelope

  def show(%{conn: conn, ingress_tunneling: ingress_tunneling}) do
    ResponseEnvelope.success(conn, ingress_tunneling)
  end
end
