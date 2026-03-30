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

auth_enabled = get_env("AUTH_ENABLED", :boolean, true)

config :edge_admin, Corsica, origins: get_env("CORS_ALLOWED_ORIGINS", :cors)

config :edge_admin, EdgeAdminWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env("API_PORT", :integer, 44_000)
  ],
  secret_key_base: get_env!("SECRET_KEY_BASE"),
  live_view: [
    signing_salt: generate_random_string(16)
  ]

config :edge_admin,
  basic_auth: [
    username: get_env("BASIC_AUTH_USERNAME"),
    password: get_env("BASIC_AUTH_PASSWORD")
  ]

config :edge_admin,
  live_dashboard_enabled: get_env("LIVE_DASHBOARD_ENABLED", :boolean, false),
  api_docs_enabled: get_env("API_DOCS_ENABLED", :boolean, true)

if auth_enabled do
  master_key = get_env!("MASTER_KEY")
  api_key = get_env("API_KEY") || master_key
  metrics_key = get_env("METRICS_KEY") || master_key
  proxy_key = get_env("PROXY_KEY") || master_key
  mcp_key = get_env("MCP_KEY") || master_key

  config :edge_admin,
    auth_enabled: true,
    master_key: master_key,
    api_key: api_key,
    metrics_key: metrics_key,
    proxy_key: proxy_key,
    mcp_key: mcp_key
else
  config :edge_admin,
    auth_enabled: false,
    master_key: nil,
    api_key: nil,
    metrics_key: nil,
    proxy_key: "",
    mcp_key: nil
end

admin_id = generate_random_string(12)

# =============================================================================
# Background Job Schedules
# =============================================================================

# --- Quantum (LocalScheduler) ---
admin_discovery_schedule = get_env("ADMIN_DISCOVERY_SCHEDULE", :string, "*/5 * * * *")
metadata_recomputation_schedule = get_env("METADATA_RECOMPUTATION_SCHEDULE", :string, "* * * * *")
node_health_check_schedule = get_env("NODE_HEALTH_CHECK_SCHEDULE", :string, "* * * * *")
execution_delivery_schedule = get_env("EXECUTION_DELIVERY_SCHEDULE", :string, "* * * * *")

# --- Oban Cron ---
zombie_admin_cleanup_schedule = get_env("ZOMBIE_ADMIN_CLEANUP_SCHEDULE", :string, "*/30 * * * *")
zombie_admin_checkin_threshold_minutes = get_env("ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES", :integer, 120)
cluster_reconciliation_schedule = get_env("CLUSTER_RECONCILIATION_SCHEDULE", :string, "0 */6 * * *")

config :edge_admin, EdgeAdmin.LocalScheduler,
  jobs: [
    admin_discovery: [
      schedule: admin_discovery_schedule,
      task: {EdgeAdmin.Admins.Discovery, :scan_and_connect_admins, []}
    ],
    metadata_recomputation: [
      schedule: metadata_recomputation_schedule,
      task: {EdgeAdmin.Admins.Metadata, :recompute_now, []}
    ],
    node_health_check: [
      schedule: node_health_check_schedule,
      task: {EdgeAdmin.Nodes, :check_node_health, []}
    ],
    execution_delivery: [
      schedule: execution_delivery_schedule,
      task: {EdgeAdmin.Commands, :deliver_local_executions, []}
    ]
  ]

config :edge_admin, EdgeAdmin.PromEx,
  disabled: false,
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    execution_creation: 10,
    zombie_admin_cleanup: 1,
    cluster_reconciliation: 10,
    self_updates: 3
  ],
  repo: EdgeAdmin.Repo,
  peer: Oban.Peers.Database,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Remove stale admin hosts from the admin VPN that haven't checked in recently
       {zombie_admin_cleanup_schedule, EdgeAdmin.Vpn.Workers.CleanupZombieAdminsWorker},
       # Reconcile clusters and nodes between DB and Netmaker
       {cluster_reconciliation_schedule, EdgeAdmin.Nodes.Workers.ScheduleClusterReconciliationWorker}
     ]},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 86_400}
  ]

# Proxy server per-operation timeouts (in milliseconds)
config :edge_admin, :proxy_timeouts,
  connection: get_env("PROXY_CONNECTION_TIMEOUT_MS", :integer, 5_000),
  handshake: get_env("PROXY_HANDSHAKE_TIMEOUT_MS", :integer, 10_000),
  read: get_env("PROXY_READ_TIMEOUT_MS", :integer, 10_000),
  recv: get_env("PROXY_RECV_TIMEOUT_MS", :integer, 300_000)

config :edge_admin,
  # === Admin Identity ===
  admin_id: admin_id,
  admin_name: EdgeAdmin.Vpn.build_vpn_name(admin_id, prefix: :admin),
  admin_max_capacity: get_env!("ADMIN_MAX_CAPACITY", :positive_integer),
  # === Admin Cluster (VPN network for multi-admin coordination) ===
  admin_cluster_name: EdgeAdmin.Vpn.build_network_name(get_env!("ADMIN_CLUSTER_NAME"), prefix: :admin),
  admin_cluster_subnet: get_env("ADMIN_CLUSTER_SUBNET"),
  # === WireGuard Configuration ===
  # Static port for WireGuard (must match UDP port mapping in docker-compose for external connectivity)
  admin_wireguard_port: get_env("ADMIN_WIREGUARD_PORT", :integer),
  # === Erlang Distribution (for multi-admin clustering) ===
  vpn_cluster_cookie: get_env("VPN_CLUSTER_COOKIE", :atom, :edge_admin_default_cookie),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 44_000),
  # === VPN & Cluster Configuration ===
  # Subnet size for auto-generated clusters (e.g., 24 = /24 = 254 hosts)
  cluster_subnet_prefix: get_env("CLUSTER_SUBNET_PREFIX", :integer, 24),
  # CIDR ranges to use for auto-generated cluster subnets (CGNAT space)
  cluster_auto_generated_ranges: get_env("CLUSTER_AUTO_GENERATED_RANGES", :list, ["100.64.0.0/10"]),
  # Slots reserved for admin gateway nodes (e.g. split-brain flooding).
  # Tune to match total admin instances across all admin clusters per core.
  admin_slot_reservation: get_env("ADMIN_SLOT_RESERVATION", :integer, 10),
  # Slots reserved for node churn headroom (reconciliation re-adds, transient failures).
  node_slot_reservation: get_env("NODE_SLOT_RESERVATION", :integer, 10),
  # Optional: Pre-defined default cluster for agent enrollment
  default_cluster_name: get_env("DEFAULT_CLUSTER_NAME"),
  default_cluster_subnet: get_env("DEFAULT_CLUSTER_SUBNET"),
  # Allow public enrollment without authentication (dev/testing only)
  public_enrollment_key_enabled: get_env("PUBLIC_ENROLLMENT_KEY_ENABLED", :boolean, false),
  # Admin URLs for enrollment key generation and agent fallback (required).
  admin_urls: get_env("ADMIN_URLS", :list),
  derp_map_url: get_env("DERP_MAP_URL"),
  # Netmaker DNS domain suffix (used for hostname construction)
  netmaker_default_domain: get_env("NETMAKER_DEFAULT_DOMAIN", :string, "nm.internal"),
  # === Background Job Schedules ===
  admin_discovery_schedule: admin_discovery_schedule,
  metadata_recomputation_schedule: metadata_recomputation_schedule,
  node_health_check_schedule: node_health_check_schedule,
  execution_delivery_schedule: execution_delivery_schedule,
  cluster_reconciliation_enabled: get_env("CLUSTER_RECONCILIATION_ENABLED", :boolean, true),
  cluster_reconciliation_schedule: cluster_reconciliation_schedule,
  zombie_admin_cleanup_schedule: zombie_admin_cleanup_schedule,
  zombie_admin_checkin_threshold_minutes: zombie_admin_checkin_threshold_minutes,
  # === VPN Sync Configuration ===
  # Sync VPN config after gateway reconciliation (default: true)
  # Disable on resource-starved machines to prevent cascading failures from interface resets
  sync_vpn_after_reconciliation: get_env("SYNC_VPN_AFTER_RECONCILIATION", :boolean, true),
  # Delete unrecognized hosts from cluster networks during reconciliation (default: true).
  evict_rogue_hosts: get_env("EVICT_ROGUE_HOSTS", :boolean, true),
  # === HTTP Request Timeouts (admin → agent) ===
  # Health checks run every minute across all owned nodes — keep tight.
  health_check_timeout: get_env("HEALTH_CHECK_TIMEOUT_MS", :integer, 3_000),
  # Metrics scraping — allow a little more for slow exporters.
  metrics_scrape_timeout: get_env("METRICS_SCRAPE_TIMEOUT_MS", :integer, 8_000),
  # Command delivery — agent may be busy, allow a bit more time.
  command_delivery_timeout: get_env("COMMAND_DELIVERY_TIMEOUT_MS", :integer, 10_000),
  # === Node Health Check ===
  node_health_check_concurrency: get_env("NODE_HEALTH_CHECK_CONCURRENCY", :integer, 100),
  # === Proxy Server Ports ===
  http_proxy_port: get_env("HTTP_PROXY_PORT", :integer, 43_128),
  socks5_proxy_port: get_env("SOCKS5_PROXY_PORT", :integer, 41_080),
  # === External Services ===
  metrics_base_url: get_env!("METRICS_BASE_URL"),
  netmaker_superadmin_username: get_env!("NETMAKER_SUPERADMIN_USERNAME"),
  netmaker_superadmin_password: get_env!("NETMAKER_SUPERADMIN_PASSWORD")

config :nexmaker,
  base_url: get_env!("NETMAKER_API_URL"),
  master_key: get_env!("NETMAKER_MASTER_KEY")

# Disable memsup (memory supervisor) from :os_mon
# We use PromEx + VictoriaMetrics for memory monitoring instead.
# memsup causes false alarms on Linux systems due to not understanding
# that cached memory is reclaimable (looks at MemFree instead of MemAvailable).
config :os_mon,
  start_memsup: false

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENVIRONMENT_NAME")
