# edge_admin/config/runtime.exs
import Config
import EdgeAdmin.Config

# =============================================================================
# Database
# =============================================================================

config :edge_admin, EdgeAdmin.Repo,
  username: get_env!("DB_USER"),
  password: get_env!("DB_PASSWORD"),
  hostname: get_env!("DB_HOST"),
  database: get_env!("DB_NAME"),
  port: get_env!("DB_PORT", :integer),
  ssl: get_env("DB_SSL", :boolean),
  pool_size: get_env!("DB_POOL_SIZE", :integer),
  socket_options: if(get_env("DB_IPV6", :boolean), do: [:inet6], else: [])

# =============================================================================
# Phoenix / Web
# =============================================================================

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean) == true do
  config :edge_admin, EdgeAdminWeb.Endpoint, server: true
end

config :edge_admin, EdgeAdminWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env!("API_PORT", :integer)
  ],
  secret_key_base: get_env!("SECRET_KEY_BASE"),
  session_key: get_env!("SESSION_KEY"),
  session_signing_salt: get_env!("SESSION_SIGNING_SALT")

config :edge_admin, Corsica, origins: get_env("CORS_ALLOWED_ORIGINS", :cors)

config :edge_admin,
  basic_auth: [
    username: get_env("BASIC_AUTH_USERNAME"),
    password: get_env("BASIC_AUTH_PASSWORD")
  ]

# =============================================================================
# Authentication
# =============================================================================

auth_enabled = get_env("AUTH_ENABLED", :boolean, true)

if auth_enabled do
  master_key = get_env!("MASTER_KEY")
  metrics_key = get_env("METRICS_KEY") || master_key

  config :edge_admin,
    auth_enabled: true,
    master_key: master_key,
    metrics_key: metrics_key
else
  config :edge_admin,
    auth_enabled: false,
    master_key: nil,
    metrics_key: nil
end

# =============================================================================
# Observability (Metrics, Telemetry, Sentry)
# =============================================================================

config :edge_admin, EdgeAdmin.PromEx,
  disabled: false,
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, EdgeAdmin.TelemetryUI, share_key: get_env("TELEMETRY_UI_SHARE_KEY")

config :edge_admin,
  metrics_storage_url: get_env("METRICS_STORAGE_URL")

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENVIRONMENT_NAME")

# =============================================================================
# VPN / Netmaker
# =============================================================================

# Nexmaker client configuration
config :nexmaker,
  base_url: get_env!("NETMAKER_API_URL"),
  master_key: get_env!("NETMAKER_MASTER_KEY")

# Netmaker superadmin (for UI access)
config :edge_admin,
  netmaker_superadmin_username: get_env!("NETMAKER_SUPERADMIN_USERNAME"),
  netmaker_superadmin_password: get_env!("NETMAKER_SUPERADMIN_PASSWORD")

# Cluster subnet generation
config :edge_admin,
  cluster_subnet_prefix: get_env("CLUSTER_SUBNET_PREFIX", :integer, 24),
  cluster_auto_generated_ranges:
    get_env("CLUSTER_AUTO_GENERATED_RANGES", :list, ["100.64.0.0/10"])

# Default cluster (optional)
config :edge_admin,
  default_cluster_name: get_env("DEFAULT_CLUSTER_NAME"),
  default_cluster_subnet: get_env("DEFAULT_CLUSTER_SUBNET")

# Admin cluster configuration
admin_id = generate_random_string(12)

config :edge_admin,
  admin_id: admin_id,
  admin_name: "admin-#{admin_id}",
  admin_cluster_name: EdgeAdmin.Vpn.build_admin_cluster_name(get_env!("ADMIN_CLUSTER_NAME")),
  admin_cluster_subnet: get_env("ADMIN_CLUSTER_SUBNET"),
  admin_max_capacity: get_env!("ADMIN_MAX_CAPACITY", :positive_integer),
  erlang_cookie: get_env!("ERLANG_COOKIE", :atom),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 4000),
  netmaker_default_domain: get_env("NETMAKER_DEFAULT_DOMAIN", :string, "nm.internal")

# =============================================================================
# Workers / Schedulers (Oban, Quantum)
# =============================================================================

# Ephemeral key cleanup configuration
ephemeral_key_cleanup_enabled = get_env("EPHEMERAL_KEY_CLEANUP_ENABLED", :boolean, true)
ephemeral_key_ttl_hours = get_env("EPHEMERAL_KEY_TTL_HOURS", :integer, 168)
ephemeral_key_cleanup_schedule = get_env("EPHEMERAL_KEY_CLEANUP_SCHEDULE", :string, "0 0 * * *")

config :edge_admin,
  ephemeral_key_cleanup_enabled: ephemeral_key_cleanup_enabled,
  ephemeral_key_ttl_hours: ephemeral_key_ttl_hours,
  ephemeral_key_cleanup_schedule: ephemeral_key_cleanup_schedule

# Oban crontab
base_crontab = [
  {"* * * * *", EdgeAdmin.Commands.Workers.ExecutionRetryWorker},
  {"* * * * *", EdgeAdmin.Nodes.Workers.NodeHealthCheckWorker},
  {"0 */6 * * *", EdgeAdmin.Admins.Workers.ZombieAdminCleaner}
]

crontab =
  if ephemeral_key_cleanup_enabled do
    base_crontab ++
      [{ephemeral_key_cleanup_schedule, EdgeAdmin.Nodes.Workers.EphemeralKeyCleanupWorker}]
  else
    base_crontab
  end

config :edge_admin, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    command_dispatch: 10,
    command_retry: 1,
    key_cleanup: 1
  ],
  repo: EdgeAdmin.Repo,
  plugins: [
    {Oban.Plugins.Cron, crontab: crontab},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 86_400}
  ]

# Quantum LocalScheduler
config :edge_admin, EdgeAdmin.LocalScheduler,
  jobs: [
    # Admin discovery - every 5 minutes
    admin_discovery: [
      schedule: "*/5 * * * *",
      task: {EdgeAdmin.Admins.Discovery, :scan_and_connect_admins, []}
    ],
    # Metadata recomputation - every 60 seconds
    metadata_recomputation: [
      schedule: "* * * * *",
      task: {EdgeAdmin.Admins.Metadata, :recompute_now, []}
    ]
  ]
