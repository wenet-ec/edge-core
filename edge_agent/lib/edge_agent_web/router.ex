# edge_agent/lib/edge_agent_web/router.ex
defmodule EdgeAgentWeb.Router do
  @moduledoc """
  Phoenix router for the agent's REST API.

  Two pipelines:

  - `:public` — JSON-accepting, no auth. Currently only the `/derp_map`
    reflection endpoint, which netclient calls without credentials.
  - `:api` — JSON + `ApiTokenAuth` (bearer token verified against the
    agent's stored API token from bootstrap registration). All
    admin↔agent endpoints sit here.

  Routes mirror what `EdgeAgent.EdgeClusters.AdminClient` documents on the
  admin side; if you add one here, update that moduledoc's endpoint list
  too.
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

    post "/self_updates/trigger", SelfUpdateController, :trigger
  end
end
