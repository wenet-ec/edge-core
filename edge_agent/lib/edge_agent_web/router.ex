# edge_agent/lib/edge_agent_web/router.ex
defmodule EdgeAgentWeb.Router do
  use EdgeAgentWeb, :router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html", "json"])
    plug(:session)
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:fetch_live_flash)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/" do
    pipe_through(:browser)
  end

  scope "/api", EdgeAgentWeb do
    pipe_through(:api)

    resources "/command-executions", CommandExecutionController, except: [:new, :edit]
  end

  # Keep the session function as TelemetryUI might need it
  defp session(conn, _opts) do
    opts = Plug.Session.init(EdgeAgentWeb.Session.config())
    Plug.Session.call(conn, opts)
  end
end
