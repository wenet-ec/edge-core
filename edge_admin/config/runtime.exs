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
  metrics_key = get_env("METRICS_KEY") || master_key
  proxy_key = get_env("PROXY_KEY") || master_key
  mcp_key = get_env("MCP_KEY") || master_key

  config :edge_admin,
    auth_enabled: true,
    master_key: master_key,
    metrics_key: metrics_key,
    proxy_key: proxy_key,
    mcp_key: mcp_key
else
  config :edge_admin,
    auth_enabled: false,
    master_key: nil,
    metrics_key: nil,
    proxy_key: "",
    mcp_key: nil
end

admin_id = generate_random_string(12)

# Cluster reconciliation configuration
cluster_reconciliation_enabled = get_env("CLUSTER_RECONCILIATION_ENABLED", :boolean, true)

cluster_reconciliation_schedule =
  get_env("CLUSTER_RECONCILIATION_SCHEDULE", :string, "0 */6 * * *")

# Zombie admin cleanup configuration
zombie_admin_cleanup_schedule = get_env("ZOMBIE_ADMIN_CLEANUP_SCHEDULE", :string, "*/30 * * * *")

zombie_admin_checkin_threshold_minutes =
  get_env("ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES", :integer, 120)

# Oban crontab
crontab =
  [
    {true, {zombie_admin_cleanup_schedule, EdgeAdmin.Vpn.Workers.ZombieAdminCleaner}},
    {cluster_reconciliation_enabled,
     {cluster_reconciliation_schedule, EdgeAdmin.Nodes.Workers.ClusterReconciliationWorker}}
  ]
  |> Enum.filter(&elem(&1, 0))
  |> Enum.map(&elem(&1, 1))

config :edge_admin, EdgeAdmin.LocalScheduler,
  jobs: [
    # Admin discovery - scan network for other admin nodes (every 5min)
    admin_discovery: [
      schedule: "*/5 * * * *",
      task: {EdgeAdmin.Admins.Discovery, :scan_and_connect_admins, []}
    ],
    # Metadata recomputation - update cluster assignments (every 1min)
    metadata_recomputation: [
      schedule: "* * * * *",
      task: {EdgeAdmin.Admins.Metadata, :recompute_now, []}
    ],
    # Node health check - ping agents to verify connectivity (configurable)
    node_health_check: [
      schedule: get_env("NODE_HEALTH_CHECK_SCHEDULE", :string, "* * * * *"),
      task: {EdgeAdmin.Nodes, :check_node_health, []}
    ],
    # Execution delivery - deliver pending commands to agents (every 1min)
    execution_delivery: [
      schedule: "* * * * *",
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
    cluster_reconciliation: 1,
    self_updates: 3
  ],
  repo: EdgeAdmin.Repo,
  peer: Oban.Peers.Database,
  plugins: [
    {Oban.Plugins.Cron, crontab: crontab},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 86_400}
  ]

config :edge_admin,
  # === Admin Identity ===
  admin_id: admin_id,
  admin_name: EdgeAdmin.Vpn.build_dns_name(admin_id, prefix: :admin),
  admin_max_capacity: get_env!("ADMIN_MAX_CAPACITY", :positive_integer),
  # === Admin Cluster (VPN network for multi-admin coordination) ===
  admin_cluster_name: EdgeAdmin.Vpn.build_network_name(get_env!("ADMIN_CLUSTER_NAME"), prefix: :admin),
  admin_cluster_subnet: get_env("ADMIN_CLUSTER_SUBNET"),
  # === WireGuard Configuration ===
  # Static port for WireGuard (must match UDP port mapping in docker-compose for external connectivity)
  admin_wireguard_port: get_env("ADMIN_WIREGUARD_PORT", :integer),
  # === Erlang Distribution (for multi-admin clustering) ===
  erlang_cookie: get_env("ERLANG_COOKIE", :atom, :edge_admin_default_cookie),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 44_000),
  # === VPN & Cluster Configuration ===
  # Subnet size for auto-generated clusters (e.g., 24 = /24 = 254 hosts)
  cluster_subnet_prefix: get_env("CLUSTER_SUBNET_PREFIX", :integer, 24),
  # CIDR ranges to use for auto-generated cluster subnets (CGNAT space)
  cluster_auto_generated_ranges: get_env("CLUSTER_AUTO_GENERATED_RANGES", :list, ["100.64.0.0/10"]),
  # Optional: Pre-defined default cluster for agent enrollment
  default_cluster_name: get_env("DEFAULT_CLUSTER_NAME"),
  default_cluster_subnet: get_env("DEFAULT_CLUSTER_SUBNET"),
  # Allow public enrollment without authentication (dev/testing only)
  public_enrollment_key_enabled: get_env("PUBLIC_ENROLLMENT_KEY_ENABLED", :boolean, false),
  # Admin URLs for enrollment key generation and agent fallback (required).
  admin_urls: get_env("ADMIN_URLS", :list),
  # Netmaker DNS domain suffix (used for hostname construction)
  netmaker_default_domain: get_env("NETMAKER_DEFAULT_DOMAIN", :string, "nm.internal"),
  # === Cleanup & Reconciliation Schedules ===
  cluster_reconciliation_enabled: cluster_reconciliation_enabled,
  cluster_reconciliation_schedule: cluster_reconciliation_schedule,
  zombie_admin_cleanup_schedule: zombie_admin_cleanup_schedule,
  zombie_admin_checkin_threshold_minutes: zombie_admin_checkin_threshold_minutes,
  # === VPN Sync Configuration ===
  # Sync VPN config after gateway reconciliation (default: true)
  # Disable on resource-starved machines to prevent cascading failures from interface resets
  sync_vpn_after_reconciliation: get_env("SYNC_VPN_AFTER_RECONCILIATION", :boolean, true),
  # Delete unrecognized hosts from cluster networks during reconciliation (default: true).
  evict_rogue_hosts: get_env("EVICT_ROGUE_HOSTS", :boolean, true),
  # === HTTP Request Timeouts ===
  # Agent communication: health checks, metrics scraping, command execution
  http_agent_receive_timeout: get_env("HTTP_AGENT_RECEIVE_TIMEOUT_MS", :integer, 10_000),
  http_agent_connect_timeout: get_env("HTTP_AGENT_CONNECT_TIMEOUT_MS", :integer, 10_000),
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
