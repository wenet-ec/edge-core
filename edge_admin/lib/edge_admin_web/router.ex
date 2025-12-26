# edge_admin/lib/edge_admin_web/router.ex
defmodule EdgeAdminWeb.Router do
  use EdgeAdminWeb, :router

  import Phoenix.LiveView.Router

  alias OpenApiSpex.Plug.PutApiSpec

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
  end

  # Public API pipeline (no authentication required)
  pipeline :public_api do
    plug(:accepts, ["json"])
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
  end

  # Protected API pipeline (requires MASTER_KEY)
  pipeline :protected_api do
    plug(:accepts, ["json"])
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
    plug(EdgeAdminWeb.Plugs.MasterKeyAuth)
  end

  # Metrics API pipeline (accepts MASTER_KEY or METRICS_KEY)
  pipeline :protected_metrics do
    plug(:accepts, ["json"])
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
    plug(EdgeAdminWeb.Plugs.MetricsAuth)
  end

  # OpenAPI pipeline (no CSRF, no auth for spec access)
  pipeline :open_api do
    plug(:accepts, ["json"])
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
  end

  # Agent API pipeline (requires agent api_token)
  pipeline :agent_api do
    plug(:accepts, ["json"])
    plug(PutApiSpec, module: EdgeAdminWeb.ApiSpec)
    plug(EdgeAdminWeb.Plugs.AgentAuth)
  end

  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through(:browser)

    # Serve SwaggerUI - this is what you'll navigate to see the docs
    get("/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi")

    # Serve ReDoc - alternative API documentation UI
    get("/redoc", Redoc.Plug.RedocUI, spec_url: "/api/openapi")

    # LiveDashboard (always mounted, but can be disabled via endpoint check)
    live_dashboard("/live_dashboard",
      metrics: EdgeAdminWeb.Telemetry,
      ecto_repos: [EdgeAdmin.Repo],
      on_mount: EdgeAdminWeb.LiveDashboardAuth,
      additional_pages: [
        oban: Oban.LiveDashboard,
        netmaker: EdgeAdminWeb.NetmakerDashboard
      ]
    )
  end

  # Serve OpenAPI spec through the open_api pipeline
  scope "/api" do
    pipe_through(:open_api)

    # Serve the OpenAPI spec as JSON
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
  end

  # Public API endpoints (no authentication required)
  scope "/api", EdgeAdminWeb.Controllers do
    pipe_through(:public_api)

    scope "/admins", Admins do
      get("/self/discovery", DiscoveryController, :index)
    end

    scope "/", Nodes do
      post("/clusters/default/enrollment_keys/public", EnrollmentKeyController, :create_for_public)
    end
  end

  # Protected admin metadata endpoints (requires MASTER_KEY)
  scope "/api", EdgeAdminWeb.Controllers do
    pipe_through(:protected_api)

    scope "/admins", Admins do
      get("/self", AdminController, :show)
      get("/admin_cluster", AdminClusterController, :show)
      get("/edge_clusters", EdgeClustersController, :index)
      get("/orphaned_clusters", OrphanedClustersController, :index)
    end
  end

  # Metrics endpoints (accepts MASTER_KEY or METRICS_KEY)
  scope "/api", EdgeAdminWeb.Controllers do
    pipe_through(:protected_metrics)

    scope "/", Nodes do
      # Prometheus HTTP service discovery
      get("/nodes/metrics/discovery", NodeMetricsDiscoveryController, :index)

      # Raw metrics proxy (per-node)
      get("/nodes/:node_id/metrics/raw", NodeMetricsDiscoveryController, :show)
    end
  end

  # Agent API endpoints (no authentication for registration)
  scope "/api/agents", EdgeAdminWeb.Controllers.Agents do
    pipe_through(:public_api)

    # Node registration (no auth required)
    post("/nodes", NodeController, :create)
  end

  # Agent API endpoints (requires agent api_token)
  scope "/api/agents", EdgeAdminWeb.Controllers.Agents do
    pipe_through(:agent_api)

    # SSH credentials verification
    post("/ssh_usernames/verify_credentials", SshUsernameController, :verify_credentials)

    # Command sync and result reporting
    get("/command_executions", CommandExecutionController, :index)
    patch("/command_executions/:id", CommandExecutionController, :update)
  end

  # Protected API endpoints (requires MASTER_KEY)
  scope "/api", EdgeAdminWeb.Controllers do
    pipe_through(:protected_api)

    scope "/", Nodes do
      # Convenience endpoint for default cluster (must come BEFORE resources)
      post("/clusters/default/enrollment_keys", EnrollmentKeyController, :create_for_default)

      # Cluster routes using name as parameter instead of id
      resources("/clusters", ClusterController, only: [:index, :show, :create, :delete], param: "name") do
        # Enrollment keys nested under clusters
        post("/enrollment_keys", EnrollmentKeyController, :create)
      end

      resources("/nodes", NodeController, only: [:index, :show]) do
        resources("/aliases", AliasController, only: [:create])
        get("/metrics", NodeMetricsController, :index)
      end

      patch("/nodes/:id/change_cluster", NodeController, :change_cluster)
      delete("/nodes/:id", NodeController, :delete)

      resources("/aliases", AliasController, only: [:index, :show, :delete])
    end

    scope "/", Ssh do
      post("/nodes/:node_id/ssh_usernames", SshUsernameController, :create)

      resources("/ssh_usernames", SshUsernameController, only: [:index, :show, :delete]) do
        resources("/ssh_public_keys", SshPublicKeyController, only: [:create])
      end

      resources("/ssh_public_keys", SshPublicKeyController, only: [:index, :show, :delete])
    end

    scope "/", Commands do
      resources("/commands", CommandController, only: [:index, :create, :show])
      delete("/commands/:id", CommandController, :delete)

      resources("/command_executions", CommandExecutionController, only: [:index, :show])
      delete("/command_executions/:id", CommandExecutionController, :delete)
    end
  end
end
