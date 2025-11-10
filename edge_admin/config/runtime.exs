# edge_admin/config/runtime.exs
import Config
import EdgeAdmin.Config

config :edge_admin, EdgeAdmin.Repo,
  username: get_env!("DB_USER"),
  password: get_env!("DB_PASSWORD"),
  hostname: get_env!("DB_HOST"),
  database: get_env!("DB_NAME"),
  port: get_env!("DB_PORT", :integer),
  ssl: get_env("DB_SSL", :boolean),
  pool_size: get_env!("DB_POOL_SIZE", :integer),
  socket_options: if(get_env("DB_IPV6", :boolean), do: [:inet6], else: [])

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean) == true do
  config :edge_admin, EdgeAdminWeb.Endpoint, server: true
end

config :edge_admin, Corsica, origins: get_env("CORS_ALLOWED_ORIGINS", :cors)

config :edge_admin, EdgeAdmin.PromEx,
  disabled: false,
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, EdgeAdmin.TelemetryUI, share_key: get_env("TELEMETRY_UI_SHARE_KEY")

config :edge_admin, EdgeAdminWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env!("API_PORT", :integer)
  ],
  secret_key_base: get_env!("SECRET_KEY_BASE"),
  session_key: get_env!("SESSION_KEY"),
  session_signing_salt: get_env!("SESSION_SIGNING_SALT")

config :edge_admin,
  basic_auth: [
    username: get_env("BASIC_AUTH_USERNAME"),
    password: get_env("BASIC_AUTH_PASSWORD")
  ]

config :edge_admin,
  metrics_storage_url: get_env("METRICS_STORAGE_URL")

# Nexmaker (Netmaker) configuration
config :nexmaker,
  base_url: get_env!("NETMAKER_API_URL"),
  master_key: get_env!("NETMAKER_MASTER_KEY")

# Netmaker Superadmin (for UI access - optional)
config :edge_admin,
  netmaker_superadmin_username: get_env!("NETMAKER_SUPERADMIN_USERNAME"),
  netmaker_superadmin_password: get_env!("NETMAKER_SUPERADMIN_PASSWORD")

# Cluster configuration
config :edge_admin,
  cluster_subnet_prefix: get_env("CLUSTER_SUBNET_PREFIX", :integer, 24),
  cluster_auto_generated_ranges:
    get_env("CLUSTER_AUTO_GENERATED_RANGES", :list, ["100.64.0.0/10"])

# Default cluster (optional - for convenience)
config :edge_admin,
  default_cluster_name: get_env("DEFAULT_CLUSTER_NAME"),
  default_cluster_subnet: get_env("DEFAULT_CLUSTER_SUBNET")

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENVIRONMENT_NAME")
