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
execution_expiration_schedule = get_env("EXECUTION_EXPIRATION_SCHEDULE", :string, "* * * * *")
vpn_config_sync_schedule = get_env("VPN_CONFIG_SYNC_SCHEDULE", :string, "*/2 * * * *")
zombie_admin_cleanup_schedule = get_env("ZOMBIE_ADMIN_CLEANUP_SCHEDULE", :string, "*/30 * * * *")

# --- Oban Cron ---
zombie_admin_checkin_threshold_minutes = get_env("ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES", :integer, 120)
cluster_reconciliation_schedule = get_env("CLUSTER_RECONCILIATION_SCHEDULE", :string, "0 */6 * * *")

# --- Prom Ex Configurations and Grafana Integration ---
grafana_config =
  case System.get_env("GRAFANA_HOST") do
    nil ->
      :disabled

    host ->
      auth =
        if token = System.get_env("GRAFANA_AUTH_TOKEN") do
          [auth_token: token]
        else
          [username: System.get_env("GRAFANA_USERNAME", "admin"), password: System.get_env("GRAFANA_PASSWORD", "")]
        end

      [
        host: host,
        upload_dashboards_on_start: System.get_env("GRAFANA_UPLOAD_ON_START", "true") == "true",
        folder_name: System.get_env("GRAFANA_FOLDER_NAME", "Edge Core"),
        annotate_app_lifecycle: System.get_env("GRAFANA_ANNOTATE_LIFECYCLE", "false") == "true"
      ] ++ auth
  end

# --- LocalScheduler  ---
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
    ],
    execution_expiration: [
      schedule: execution_expiration_schedule,
      task: {EdgeAdmin.Commands, :expire_stale_executions, []}
    ],
    vpn_config_sync: [
      schedule: vpn_config_sync_schedule,
      task: {EdgeAdmin.Vpn, :sync_vpn_config, []}
    ],
    zombie_admin_cleanup: [
      schedule: zombie_admin_cleanup_schedule,
      task: {EdgeAdmin.Vpn, :run_zombie_admin_cleanup, []}
    ]
  ]

config :edge_admin, EdgeAdmin.PromEx,
  disabled: !get_env("ADMIN_METRICS_ENABLED", :boolean, true),
  grafana: grafana_config,
  metrics_server: :disabled

# Queue concurrency note:
# In production, up to 200 admin instances may share the same PostgreSQL.
# Each admin instance opens one polling connection per queue. Keep concurrency
# low — the bottleneck is DB connection pressure, not throughput.
#
#   execution_creation     — inserts execution records in bulk; 2 is plenty
#   cluster_reconciliation — one job per cluster every 6h; 1 is enough
#   self_updates           — rare, triggered manually; 1 is fine
#   event_broker           — async broker publish with retry; 2 keeps it snappy
#                          without hammering the broker with parallel calls
config :edge_admin, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    execution_creation: 2,
    cluster_reconciliation: 1,
    self_updates: 1,
    event_broker: 2
  ],
  repo: EdgeAdmin.Repo,
  peer: Oban.Peers.Database,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Reconcile clusters and nodes between DB and Netmaker
       {cluster_reconciliation_schedule, EdgeAdmin.Nodes.Workers.ScheduleClusterReconciliationWorker}
     ]},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 86_400}
  ]

# Proxy server per-operation timeouts (in milliseconds)
config :edge_admin, :proxy_timeouts,
  connection: get_env("PROXY_CONNECTION_TIMEOUT_MS", :integer, 2_000),
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
  default_cluster_node_limit: get_env("DEFAULT_CLUSTER_NODE_LIMIT", :integer),
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
  execution_expiration_schedule: execution_expiration_schedule,
  vpn_config_sync_schedule: vpn_config_sync_schedule,
  cluster_reconciliation_enabled: get_env("CLUSTER_RECONCILIATION_ENABLED", :boolean, true),
  cluster_reconciliation_schedule: cluster_reconciliation_schedule,
  zombie_admin_cleanup_schedule: zombie_admin_cleanup_schedule,
  zombie_admin_checkin_threshold_minutes: zombie_admin_checkin_threshold_minutes,
  # === VPN Sync Configuration ===
  # Disable periodic VPN config sync on severely resource-starved machines (default: true)
  vpn_config_sync_enabled: get_env("VPN_CONFIG_SYNC_ENABLED", :boolean, true),
  # Delete unrecognized hosts from cluster networks during reconciliation (default: true).
  evict_rogue_hosts: get_env("EVICT_ROGUE_HOSTS", :boolean, true),
  # === HTTP Request Timeouts (admin → agent) ===
  # Health checks run every minute across all owned nodes — keep tight.
  health_check_timeout: get_env("HEALTH_CHECK_TIMEOUT_MS", :integer, 10_000),
  # Metrics scraping — allow a little more for slow exporters.
  metrics_scrape_timeout: get_env("METRICS_SCRAPE_TIMEOUT_MS", :integer, 10_000),
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

# =============================================================================
# Event Broker
# =============================================================================
# Set EVENT_BROKER_ENABLED=true to enable. When disabled (default), all
# publish calls are immediate no-ops — no connections, no processes started.
#
# When enabled, EVENT_BROKER_ADAPTER and EVENT_BROKER_URLS are required.
#
# NATS JetStream:
#   EVENT_BROKER_ENABLED=true
#   EVENT_BROKER_ADAPTER=nats_js
#   EVENT_BROKER_URLS=nats://edge_event_broker_nats:4222          # comma-separated for cluster
#   EVENT_BROKER_NATS_TOKEN=    # optional, set if NATS auth is enabled
#
# Kafka / Redpanda:
#   EVENT_BROKER_ENABLED=true
#   EVENT_BROKER_ADAPTER=kafka
#   EVENT_BROKER_URLS=edge_event_broker_kafka:9092                # comma-separated for cluster
#   EVENT_BROKER_KAFKA_USERNAME=admin    # optional, omit if no auth
#   EVENT_BROKER_KAFKA_PASSWORD=secret   # optional, omit if no auth
#   EVENT_BROKER_KAFKA_SASL_MECHANISM=plain   # plain (default), scram_sha_256, scram_sha_512
#   EVENT_BROKER_KAFKA_SSL=true          # enable TLS — required for external brokers
#
# Core identifier — included in every event envelope for multi-core setups:
#   CORE_NAME=prod-us
config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENVIRONMENT_NAME")

if get_env("EVENT_BROKER_ENABLED", :boolean, false) do
  event_broker_adapter =
    case get_env!("EVENT_BROKER_ADAPTER") do
      "nats_js" -> :nats_js
      "kafka" -> :kafka
      other -> raise "Unknown EVENT_BROKER_ADAPTER=#{other} — valid values: nats_js, kafka"
    end

  event_broker_urls = get_env!("EVENT_BROKER_URLS")

  config :edge_admin,
    event_broker_enabled: true,
    event_broker_adapter: event_broker_adapter,
    core_name: get_env("CORE_NAME", :string, "default")

  case event_broker_adapter do
    :nats_js ->
      # Parse "nats://host:port" or "nats://host1:port1,nats://host2:port2"
      urls =
        event_broker_urls
        |> String.split(",")
        |> Enum.map(&String.trim/1)

      config :edge_admin, :event_broker_nats,
        urls: urls,
        token: get_env("EVENT_BROKER_NATS_TOKEN")

    :kafka ->
      # Parse "host:port" or "host1:port1,host2:port2"
      brokers =
        event_broker_urls
        |> String.split(",")
        |> Enum.map(fn endpoint ->
          [host, port_str] = String.split(String.trim(endpoint), ":")
          {host, String.to_integer(port_str)}
        end)

      kafka_username = get_env("EVENT_BROKER_KAFKA_USERNAME")
      kafka_password = get_env("EVENT_BROKER_KAFKA_PASSWORD")

      kafka_sasl_mechanism =
        case get_env("EVENT_BROKER_KAFKA_SASL_MECHANISM", :string, "plain") do
          "plain" ->
            :plain

          "scram_sha_256" ->
            :scram_sha_256

          "scram_sha_512" ->
            :scram_sha_512

          other ->
            raise "Unknown EVENT_BROKER_KAFKA_SASL_MECHANISM=#{other} — valid values: plain, scram_sha_256, scram_sha_512"
        end

      sasl_opts =
        if kafka_username && kafka_password do
          [sasl: {kafka_sasl_mechanism, kafka_username, kafka_password}]
        else
          []
        end

      ssl_opts =
        if get_env("EVENT_BROKER_KAFKA_SSL", :boolean, false) do
          [ssl: true]
        else
          []
        end

      config :edge_admin, :event_broker_kafka,
        brokers: brokers,
        client_config: sasl_opts ++ ssl_opts
  end
end
