# edge_admin/lib/edge_admin_web/router.ex
defmodule EdgeAdminWeb.Router do
  use EdgeAdminWeb, :router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  alias EdgeAdminWeb.Controllers.Agents
  alias EdgeAdminWeb.Plugs.ApiDocsEnabled

  pipeline :admin_debug_dashboard do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:admin_debug_dashboard_auth)
  end

  pipeline :public_api do
    plug(:accepts, ["json"])
  end

  pipeline :protected_api do
    plug(:accepts, ["json"])
    plug(EdgeAdminWeb.Plugs.ApiKeyAuth)
  end

  pipeline :mcp do
    plug(EdgeAdminWeb.Plugs.McpAuth)
  end

  pipeline :protected_metrics do
    plug(:accepts, ["json"])
    plug(EdgeAdminWeb.Plugs.MetricsAuth)
  end

  pipeline :api_specs do
    plug(:accepts, ["json"])
    plug(ApiDocsEnabled)
  end

  pipeline :api_docs_ui do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(ApiDocsEnabled)
  end

  pipeline :agent_api do
    plug(:accepts, ["json"])
    plug(EdgeAdminWeb.Plugs.AgentAuth)
  end

  # Edge Admin guide — part of the documentation surface, gated with Swagger,
  # ReDoc, AsyncAPI, and the raw specs by API_DOCS_ENABLED.
  scope "/" do
    pipe_through(:api_docs_ui)

    get("/", EdgeAdminWeb.Controllers.Guide.IndexController, :index)
    get("/guide/clusters", EdgeAdminWeb.Controllers.Guide.ClusterController, :show)
    get("/guide/nodes", EdgeAdminWeb.Controllers.Guide.NodeController, :show)
    get("/guide/commands", EdgeAdminWeb.Controllers.Guide.CommandController, :show)
    get("/guide/proxy", EdgeAdminWeb.Controllers.Guide.ProxyController, :show)
    get("/guide/ssh", EdgeAdminWeb.Controllers.Guide.SshController, :show)
    get("/guide/metrics", EdgeAdminWeb.Controllers.Guide.MetricsController, :show)
    get("/guide/events", EdgeAdminWeb.Controllers.Guide.EventController, :show)
  end

  scope "/" do
    pipe_through(:api_docs_ui)

    get("/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/openapi",
      swagger_ui_css_url: "/assets/swagger-edge-core.css"
    )

    get("/redoc", EdgeAdminWeb.Plugs.RedocUI, spec_url: "/api/openapi")
    get("/asyncdoc", EdgeAdminWeb.Controllers.AsyncApi.DocController, :show)
  end

  scope "/" do
    pipe_through(:admin_debug_dashboard)

    # ecto_stats auto-discovers the running repo at mount time via
    # Ecto.Repo.all_running/0 (see EctoStatsPage.auto_discover/1). The page
    # then dispatches per repo's adapter (Postgres → EctoPSQLExtras, SQLite
    # → EctoSQLite3Extras), so DB_ADAPTER selects the right backend with no
    # hardcoded list here.
    live_dashboard("/admin/debug",
      metrics: EdgeAdminWeb.Telemetry,
      home_app: {"Edge Admin", :edge_admin},
      on_mount: [EdgeAdminWeb.AdminDebugDashboard, EdgeAdminWeb.AdminDebugHooks],
      additional_pages: [
        oban: Oban.LiveDashboard,
        quantum: EdgeAdminWeb.Live.QuantumDashboard,
        membership: EdgeAdminWeb.Live.MembershipDashboard
      ]
    )
  end

  scope "/api" do
    pipe_through(:api_specs)

    get("/openapi", EdgeAdminWeb.Plugs.RenderOpenApiSpec, [])
    get("/asyncapi", EdgeAdminWeb.Controllers.AsyncApi.SpecController, :show)
  end

  scope "/api/v1", EdgeAdminWeb.Controllers do
    pipe_through(:public_api)

    scope "/admins", Admins do
      get("/me/discovery", DiscoveryController, :index)
    end

    scope "/", Nodes do
      post("/clusters/default/enrollment_keys/public", EnrollmentKeyController, :create_for_public)
    end
  end

  scope "/api/v1", EdgeAdminWeb.Controllers do
    pipe_through(:protected_api)

    scope "/admins", Admins do
      get("/me", AdminController, :show)
      get("/my_admin_cluster", AdminClusterController, :show)
      get("/admin_clusters", AdminClustersController, :index)
      get("/edge_clusters", EdgeClustersController, :index)
      get("/orphaned_clusters", OrphanedClustersController, :index)
    end
  end

  scope "/api/v1", EdgeAdminWeb.Controllers do
    pipe_through(:protected_metrics)

    scope "/", Metrics do
      get("/nodes/metrics/host/discovery", HostMetricsDiscoveryController, :index)
      get("/nodes/:node_id/metrics/host/raw", HostMetricsController, :show)
      get("/nodes/metrics/agent/discovery", AgentMetricsDiscoveryController, :index)
      get("/nodes/:node_id/metrics/agent/raw", AgentMetricsController, :show)
      get("/nodes/metrics/wireguard/discovery", WireguardMetricsDiscoveryController, :index)
      get("/nodes/:node_id/metrics/wireguard/raw", WireguardMetricsController, :show)
      get("/nodes/:node_id/metrics", NodeMetricsController, :show_unified)
      get("/nodes/:node_id/metrics/host", NodeMetricsController, :show_host)
      get("/nodes/:node_id/metrics/agent", NodeMetricsController, :show_agent)
      get("/admins/me/metrics", AdminMetricsController, :show)
    end
  end

  scope "/api/v1/agents", Agents do
    pipe_through(:public_api)

    post("/nodes/register", NodeController, :register)
    post("/enrollment_keys/verify", EnrollmentKeyController, :verify)
  end

  scope "/api/v1/agents", Agents do
    pipe_through(:agent_api)

    post("/nodes/reregister", NodeController, :reregister)
    post("/nodes/me/health_check", NodeController, :update_health_check)
    post("/diagnostics/push", NodeDiagnosticController, :push)
    post("/ssh_usernames/verify_credentials", SshUsernameController, :verify_credentials)
    get("/command_executions", CommandExecutionController, :index)
    post("/command_executions/:id/acknowledge", CommandExecutionController, :acknowledge)
    post("/command_executions/:id/report_result", CommandExecutionController, :report_result)
    get("/self_updates/check", SelfUpdateController, :check)
    post("/metrics/push", MetricsController, :push)
    post("/aliases", AliasController, :create)

    # Refreshable, non-secret Settings Config.
    get("/settings/config", SettingsController, :config)
  end

  scope "/api/v1", EdgeAdminWeb.Controllers do
    pipe_through(:protected_api)

    scope "/", Nodes do
      # Convenience endpoint for default cluster (must come BEFORE cluster resources)
      post("/clusters/default/enrollment_keys", EnrollmentKeyController, :create_for_default)

      # Cluster routes using name as parameter instead of id
      resources("/clusters", ClusterController, only: [:index, :show, :create, :delete], param: "name") do
        # Enrollment key creation nested under cluster
        post("/enrollment_keys", EnrollmentKeyController, :create)
      end

      patch("/clusters/:name", ClusterController, :update)

      resources("/enrollment_keys", EnrollmentKeyController, only: [:index, :show, :delete])
      patch("/enrollment_keys/:id", EnrollmentKeyController, :update)

      resources("/nodes", NodeController, only: [:index, :show]) do
        resources("/aliases", AliasController, only: [:create])
      end

      get("/nodes/:id/diagnostics", NodeDiagnosticController, :show)
      post("/nodes/:id/change_cluster", NodeController, :change_cluster)
      delete("/nodes/:id", NodeController, :delete)

      post("/nodes/:id/recovery_key", NodeRecoveryKeyController, :create)
      delete("/nodes/:id/recovery_key", NodeRecoveryKeyController, :delete)

      resources("/aliases", AliasController, only: [:index, :show, :delete])
    end

    scope "/", Ssh do
      post("/nodes/:node_id/ssh_usernames", SshUsernameController, :create)

      resources("/ssh_usernames", SshUsernameController, only: [:index, :show, :delete]) do
        resources("/ssh_public_keys", SshPublicKeyController, only: [:create])
      end

      resources("/ssh_public_keys", SshPublicKeyController, only: [:index, :show, :delete])
    end

    scope "/", Events do
      post("/events/test", EventController, :test)
      resources("/webhooks", WebhookController, only: [:index, :show, :create, :delete])
      get("/event_types", EventTypeController, :index)
    end

    scope "/", Commands do
      resources("/commands", CommandController, only: [:index, :create, :show])
      delete("/commands/:id", CommandController, :delete)

      resources("/command_executions", CommandExecutionController, only: [:index, :show])
      delete("/command_executions/:id", CommandExecutionController, :delete)
      post("/command_executions/:id/cancel", CommandExecutionController, :cancel)
    end

    resources("/self_update_requests", SelfUpdates.SelfUpdateRequestController, only: [:index, :create, :show, :delete])
  end

  scope "/" do
    pipe_through(:mcp)

    forward("/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: EdgeAdminMcp.Server)
  end

  # Admin Debug Dashboard authentication helper.
  #
  # Behaviour is controlled by `:admin_debug_auth_enabled` (default `true`):
  # - `true`  → require username + password from `:admin_debug_dashboard_auth` config; raise at
  #             request time if either is missing (loud failure beats silent open)
  # - `false` → explicitly bypass dashboard authentication
  #
  # The previous behaviour silently passed through when credentials were unset,
  # which masks a misconfigured prod admin. Set ADMIN_DEBUG_AUTH_ENABLED=true in
  # production deployments.
  defp admin_debug_dashboard_auth(conn, _opts) do
    if Application.get_env(:edge_admin, :admin_debug_auth_enabled, true) do
      dashboard_auth = Application.get_env(:edge_admin, :admin_debug_dashboard_auth, [])

      if !(dashboard_auth[:username] && dashboard_auth[:password]) do
        raise "ADMIN_DEBUG_AUTH_ENABLED=true but Admin Debug Dashboard username or password is missing"
      end

      Plug.BasicAuth.basic_auth(conn, dashboard_auth)
    else
      conn
    end
  end
end
