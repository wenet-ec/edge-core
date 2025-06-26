# edge_admin/lib/edge_admin_web/router.ex
defmodule EdgeAdminWeb.Router do
  use EdgeAdminWeb, :router

  import Phoenix.LiveView.Router

  alias OpenApiSpex.Plug.PutApiSpec

  pipeline :browser do
    plug(:accepts, ["html", "json"])
    plug(:session)
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:fetch_live_flash)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    # Add the OpenApiSpex plug to make the spec available
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
  end

  # Add a new pipeline for OpenAPI that doesn't have CSRF protection
  pipeline :openapi do
    plug(:accepts, ["json"])
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
  end

  scope "/" do
    pipe_through(:browser)

    # Serve SwaggerUI - this is what you'll navigate to see the docs
    get("/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi")

    # To enable metrics dashboard use `telemetry_ui_allowed: true` as assigns value
    #
    # Metrics can contains sensitive data you should protect it under authorization
    # See https://github.com/mirego/telemetry_ui#security
    get("/metrics", TelemetryUI.Web, [], assigns: %{telemetry_ui_allowed: true})
  end

  # Serve OpenAPI spec through the openapi pipeline
  scope "/api" do
    pipe_through(:openapi)

    # Serve the OpenAPI spec as JSON
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
  end

  scope "/api", EdgeAdminWeb do
    pipe_through(:api)

    scope "/", VPN do
      scope "/connections" do
        get("/self", ConnectionController, :show)
        patch("/self", ConnectionController, :update)
      end
    end

    scope "/", Nodes do
      resources("/enrollment_keys", EnrollmentKeyController, only: [:create])

      resources("/nodes", NodeController, only: [:index, :create, :show]) do
        resources("/ssh_usernames", SshUsernameController, only: [:create])
      end

      patch("/nodes/:id", NodeController, :update)

      resources("/ssh_usernames", SshUsernameController, only: [:index, :show, :delete]) do
        resources("/ssh_public_keys", SshPublicKeyController, only: [:create])
      end

      resources("/ssh_public_keys", SshPublicKeyController, only: [:index, :show, :delete])

      get("/metrics/discovery", MetricsDiscoveryController, :index)
    end

    scope "/", Commands do
      resources("/commands", CommandController, only: [:index, :create, :show])

      resources("/command_executions", CommandExecutionController, only: [:index, :show])
      patch("/command_executions/:id", CommandExecutionController, :update)
    end
  end

  # Keep the session function as TelemetryUI might need it
  defp session(conn, _opts) do
    opts = Plug.Session.init(EdgeAdminWeb.Session.config())
    Plug.Session.call(conn, opts)
  end
end
