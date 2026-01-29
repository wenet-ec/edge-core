# edge_admin/lib/edge_admin_web/router.ex
defmodule EdgeAdminWeb.Router do
  use EdgeAdminWeb, :router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  alias EdgeAdminWeb.Controllers.Agents
  alias OpenApiSpex.Plug.PutApiSpec

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
  end

  # Browser pipeline with basic auth (for LiveDashboard only)
  pipeline :browser_with_basic_auth do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:basic_auth)
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

  scope "/" do
    pipe_through(:browser)

    # Serve SwaggerUI - this is what you'll navigate to see the docs
    get("/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi")

    # Serve ReDoc - alternative API documentation UI
    get("/redoc", Redoc.Plug.RedocUI, spec_url: "/api/openapi")
  end

  # LiveDashboard with basic auth protection
  scope "/" do
    pipe_through(:browser_with_basic_auth)

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

    scope "/", Metrics do
      # Prometheus HTTP service discovery for host metrics
      get("/nodes/metrics/host/discovery", HostMetricsDiscoveryController, :index)

      # Raw host metrics proxy (per-node)
      get("/nodes/:node_id/metrics/host/raw", HostMetricsController, :show)

      # Prometheus HTTP service discovery for agent metrics
      get("/nodes/metrics/agent/discovery", AgentMetricsDiscoveryController, :index)

      # Raw agent metrics proxy (per-node)
      get("/nodes/:node_id/metrics/agent/raw", AgentMetricsController, :show)

      # Prometheus HTTP service discovery for WireGuard metrics
      get("/nodes/metrics/wireguard/discovery", WireguardMetricsDiscoveryController, :index)

      # Raw WireGuard metrics proxy (per-node)
      get("/nodes/:node_id/metrics/wireguard/raw", WireguardMetricsController, :show)

      # Node metrics endpoints (human-friendly)
      get("/nodes/:node_id/metrics", NodeMetricsController, :show_unified)
      get("/nodes/:node_id/metrics/host", NodeMetricsController, :show_host)
      get("/nodes/:node_id/metrics/agent", NodeMetricsController, :show_agent)

      # Admin metrics endpoints (human-friendly)
      get("/admins/metrics/self", AdminMetricsController, :show_self)
    end
  end

  # Agent API endpoints (no authentication for registration)
  scope "/api/agents", Agents do
    pipe_through(:public_api)

    # Node registration (no auth required)
    post("/nodes", NodeController, :create)
  end

  # Agent API endpoints (requires agent api_token)
  scope "/api/agents", Agents do
    pipe_through(:agent_api)

    # Node health check reporting
    patch("/nodes/me/health_check", NodeController, :update_health_check)

    # Relay gateway registration
    post("/relays", RelayController, :create)

    # SSH credentials verification
    post("/ssh_usernames/verify_credentials", SshUsernameController, :verify_credentials)

    # Command sync and result reporting
    get("/command_executions", CommandExecutionController, :index)
    patch("/command_executions/:id/acknowledge", CommandExecutionController, :acknowledge)
    patch("/command_executions/:id/result", CommandExecutionController, :update_result)

    # Self-update check
    get("/self_updates/check", SelfUpdateController, :check)

    # Metrics cache push
    post("/metrics/push", MetricsController, :push)
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
      patch("/command_executions/:id/cancel", CommandExecutionController, :cancel)
    end

    resources("/self_update_requests", SelfUpdates.SelfUpdateRequestController, only: [:index, :create, :show, :delete])
  end

  # Basic auth helper for LiveDashboard
  defp basic_auth(conn, _opts) do
    basic_auth_config = Application.get_env(:edge_admin, :basic_auth)

    if basic_auth_config[:username] do
      Plug.BasicAuth.basic_auth(conn, basic_auth_config)
    else
      conn
    end
  end
end
