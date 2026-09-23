# edge_agent/lib/edge_agent_web/router.ex
defmodule EdgeAgentWeb.Router do
  @moduledoc """
  Phoenix router for the agent's REST API.

  The public pipeline serves unauthenticated JSON endpoints required for VPN
  reflection. The API pipeline applies bearer-token authentication to
  Admin-to-Agent operations.
  """

  use EdgeAgentWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(EdgeAgentWeb.Plugs.ApiTokenAuth)
  end

  pipeline :public do
    plug(:accepts, ["json"])
  end

  scope "/api/v1", EdgeAgentWeb.Controllers do
    pipe_through(:public)

    get "/derp_map", DerpMapController, :show
  end

  scope "/api/v1", EdgeAgentWeb.Controllers do
    pipe_through(:api)

    post "/command_executions", CommandExecutionController, :create
    post "/command_executions/:id/cancel", CommandExecutionController, :cancel
    post "/ingress_tunneling", IngressTunnelingController, :create

    post "/self_updates/trigger", SelfUpdateController, :trigger

    get "/diagnostics", DiagnosticsController, :show
  end
end
