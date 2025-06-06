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

    # To enable metrics dashboard use `telemetry_ui_allowed: true` as assigns value
    #
    # Metrics can contains sensitive data you should protect it under authorization
    # See https://github.com/mirego/telemetry_ui#security
    get("/metrics", TelemetryUI.Web, [], assigns: %{telemetry_ui_allowed: true})
  end

  scope "/api", EdgeAgentWeb do
    pipe_through(:api)

    # Your API routes will go here
  end

  # Keep the session function as TelemetryUI might need it
  defp session(conn, _opts) do
    opts = Plug.Session.init(EdgeAgentWeb.Session.config())
    Plug.Session.call(conn, opts)
  end
end
