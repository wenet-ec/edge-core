# edge_agent/lib/edge_agent_web/router.ex
defmodule EdgeAgentWeb.Router do
  use EdgeAgentWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(EdgeAgentWeb.Plugs.ApiTokenAuth)
  end

  scope "/api", EdgeAgentWeb.Controllers do
    pipe_through(:api)

    resources "/command_executions", CommandExecutionController, only: [:create]
    patch "/command_executions/:id/cancel", CommandExecutionController, :cancel

    post "/self_updates/trigger", SelfUpdateController, :trigger
  end
end
