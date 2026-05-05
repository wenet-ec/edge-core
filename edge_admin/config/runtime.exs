# edge_admin/config/runtime.exs
import Config
import EdgeAdmin.Config

alias EdgeAdmin.Repo.Postgres
alias EdgeAdmin.Repo.Postgres.Notifier
alias EdgeAdmin.Repo.SQLite

###
# Database adapter selection at RUNTIME via DB_ADAPTER. The same compiled
# binary supports both modes — both EdgeAdmin.Repo.Postgres and
# EdgeAdmin.Repo.SQLite are baked in. We pick the impl module here, set
# :ecto_repos to that module so migrations and the supervisor start the
# right one, and configure only that impl with DB credentials.
#
#   postgres (default) — required for multi-admin Erlang clustering. Configured
#                        via DATABASE_URL (URL form) or DB_HOST/DB_PORT/...
#                        (fragment form). The Oban LISTEN notifier resolves
#                        independently and must use DATABASE_NOTIFIER_URL when
#                        the main repo uses URL form.
#
#   sqlite             — single-instance only, no external DB. Uses
#                        SQLITE_DB_PATH (default: /app/data/edge/edge_admin.db).
###

###
# Cloak vault — encryption-at-rest for sensitive Ecto columns.
#
# CLOAK_KEY: 32 bytes of base64. Generate with: openssl rand -base64 32
# CLOAK_TAG: short identifier prepended to every ciphertext blob, paired 1:1
#            with the key. Convention: AES.GCM.V1 / V2 / ... bumped each
#            rotation. Cloak uses the tag on read to look up which cipher in
#            the vault config matches, so the DB schema needs no version
#            column — the ciphertext is self-describing.
#
# Both required at boot. Same shape as MASTER_KEY / SECRET_KEY_BASE; if
# CLOAK_KEY is lost, every encrypted row is unrecoverable, so back it up
# alongside the rest of your secrets.
#
# Rotation is operated through `EdgeAdmin.Release.rotate_cloak_key/0` and
# the four ROTATE_OLD_CLOAK_KEY / ROTATE_OLD_CLOAK_TAG / ROTATE_NEW_CLOAK_KEY
# / ROTATE_NEW_CLOAK_TAG env vars; the active CLOAK_KEY/CLOAK_TAG below
# describes only the currently-active cipher.
###
cloak_key =
  case Base.decode64(get_env!("CLOAK_KEY")) do
    {:ok, bytes} when byte_size(bytes) == 32 ->
      bytes

    {:ok, bytes} ->
      raise """
      CLOAK_KEY decoded to #{byte_size(bytes)} bytes — must be 32 (AES-256).
      Generate one with: openssl rand -base64 32
      """

    :error ->
      raise "CLOAK_KEY is not valid base64. Generate one with: openssl rand -base64 32"
  end

cloak_tag = get_env!("CLOAK_TAG")

db_adapter =
  case get_env("DB_ADAPTER", :string, "postgres") do
    "sqlite" -> :sqlite
    _ -> :postgres
  end

repo_impl =
  case db_adapter do
    :sqlite -> SQLite
    :postgres -> Postgres
  end

config :edge_admin, EdgeAdmin.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: cloak_tag, key: cloak_key}
  ]

config :edge_admin, :db_adapter, db_adapter
config :edge_admin, :repo_impl, repo_impl
config :edge_admin, ecto_repos: [repo_impl]

case db_adapter do
  :sqlite ->
    config :edge_admin, SQLite,
      database: get_env("SQLITE_DB_PATH", :string, "/app/data/edge/edge_admin.db"),
      pool_size: get_env("DB_POOL_SIZE", :integer, 5)

  :postgres ->
    ###
    # Postgres has two configuration styles, all-or-nothing per repo:
    #
    #   1. URL form — set DATABASE_URL (and DATABASE_NOTIFIER_URL for the notifier).
    #      The URL encodes host, port, db, user, password. pool_size, ssl, and
    #      ipv6 still come from their dedicated env vars — URLs don't carry those.
    #
    #   2. Fragment form — set DB_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD
    #      (and DB_NOTIFIER_HOST / DB_NOTIFIER_PORT for the notifier).
    #
    # It's all-or-nothing per repo: if DATABASE_URL is set, every fragment is
    # ignored for that repo. The notifier resolves independently — DATABASE_URL
    # does NOT cascade to the notifier. This is intentional: in prod the main
    # repo points at PgBouncer and the notifier needs a direct primary connection,
    # so they must be configured separately.
    ###

    # When DATABASE_URL is set for the main repo, DATABASE_NOTIFIER_URL must be
    # set too. In URL mode the fragment env vars (DB_HOST, etc.) are not
    # guaranteed to exist, so we can't fall back to them for the notifier.
    if get_env("DATABASE_URL") && !get_env("DATABASE_NOTIFIER_URL") do
      raise """
      DATABASE_URL is set but DATABASE_NOTIFIER_URL is not.

      These two repos are configured independently. When you use URL mode for
      the main repo, you must also use URL mode for the notifier — typically
      pointing it at the primary directly to bypass any pooler.

      Either set DATABASE_NOTIFIER_URL, or switch the main repo back to
      fragment form (DB_HOST + DB_PORT + DB_NAME + DB_USER + DB_PASSWORD).
      """
    end

    repo_config = fn url_var, host_var, port_var ->
      base =
        case get_env(url_var) do
          nil ->
            [
              username: get_env!("DB_USER"),
              password: get_env!("DB_PASSWORD"),
              database: get_env!("DB_NAME"),
              hostname: get_env!(host_var),
              port: get_env!(port_var, :integer)
            ]

          url ->
            [url: url]
        end

      base ++
        [
          ssl: get_env("DB_SSL", :boolean),
          socket_options: if(get_env("DB_IPV6", :boolean), do: [:inet6], else: [])
        ]
    end

    # Migration lock strategy. Default: pg_advisory_lock.
    #   pg_advisory_lock  — Default. Uses pg_try_advisory_lock outside any
    #                       txn. Clean correctness story for direct-to-Postgres
    #                       deployments. Requires session-mode DB connection,
    #                       so when running behind PgBouncer transaction-mode
    #                       pooling, point migrations at the primary directly
    #                       (same pattern as DATABASE_NOTIFIER_URL).
    #   disabled          — No DB-level lock. The migrate sidecar
    #                       (deploy/{local,production}/compose/edge_admin/
    #                       migrate) is the only thing serializing concurrent
    #                       admins. Use only when an advisory lock is not
    #                       viable (e.g. PgBouncer with no direct-to-primary
    #                       route for migrations).
    #
    # Note: Ecto's own :table_lock default is deliberately not exposed here.
    # Its two-txn implementation (lock-holder + Task running DDL) has
    # historically deadlocked on this codebase under heavy DDL even with a
    # single admin.
    migration_lock =
      case get_env("DB_MIGRATION_LOCK", :string, "pg_advisory_lock") do
        "pg_advisory_lock" ->
          :pg_advisory_lock

        "disabled" ->
          nil

        other ->
          raise "invalid DB_MIGRATION_LOCK=#{inspect(other)} (expected: pg_advisory_lock | disabled)"
      end

    # Dedicated repo for Oban.Notifiers.Postgres LISTEN connection. In prod,
    # point at the primary -rw service to bypass PgBouncer, whose transaction-mode
    # pooling breaks session-pinned LISTEN. Fragment-form fallbacks: DB_NOTIFIER_HOST
    # defaults to DB_HOST, DB_NOTIFIER_PORT defaults to DB_PORT.
    config :edge_admin,
           Notifier,
           repo_config.(
             "DATABASE_NOTIFIER_URL",
             if(System.get_env("DB_NOTIFIER_HOST"), do: "DB_NOTIFIER_HOST", else: "DB_HOST"),
             if(System.get_env("DB_NOTIFIER_PORT"), do: "DB_NOTIFIER_PORT", else: "DB_PORT")
           ) ++ [pool_size: 2]

    config :edge_admin,
           Postgres,
           repo_config.("DATABASE_URL", "DB_HOST", "DB_PORT") ++
             [
               pool_size: get_env!("DB_POOL_SIZE", :integer),
               migration_lock: migration_lock
             ]
end

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean) == true do
  config :edge_admin, EdgeAdminWeb.Endpoint, server: true
end

auth_enabled = get_env("AUTH_ENABLED", :boolean, true)

# CORS — origins and allowed request headers. Set CORS_ALLOWED_HEADERS=*
# to mirror request headers back (Corsica's :all), or pass a comma-separated
# explicit list. Defaults to a small safe set covering this API's auth surface.
cors_headers =
  case get_env("CORS_ALLOWED_HEADERS") do
    nil -> ["authorization", "content-type", "x-request-id"]
    "*" -> :all
    csv -> csv |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
  end

config :edge_admin, Corsica,
  origins: get_env("CORS_ALLOWED_ORIGINS", :cors),
  allow_headers: cors_headers

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
  basic_auth_enabled: get_env("BASIC_AUTH_ENABLED", :boolean, false),
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
vpn_config_sync_schedule = get_env("VPN_CONFIG_SYNC_SCHEDULE", :string, "*/5 * * * *")
zombie_admin_cleanup_schedule = get_env("ZOMBIE_ADMIN_CLEANUP_SCHEDULE", :string, "*/30 * * * *")
zombie_admin_checkin_threshold_minutes = get_env("ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES", :integer, 120)

# --- Oban Cron ---
cluster_reconciliation_schedule = get_env("CLUSTER_RECONCILIATION_SCHEDULE", :string, "0 */6 * * *")
execution_pruning_enabled = get_env("EXECUTION_PRUNING_ENABLED", :boolean, false)
execution_pruning_schedule = get_env("EXECUTION_PRUNING_SCHEDULE", :string, "0 0 * * *")
execution_retention_days = get_env("EXECUTION_RETENTION_DAYS", :integer, 30)

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

# --- Oban engine + peer + notifier (DB-adapter dependent) ---
# SQLite uses Oban.Engines.Lite + Oban.Peers.Isolated (in-memory Agent — no
# oban_peers table) + Oban.Notifiers.PG (Erlang :pg, no LISTEN/NOTIFY).
# Postgres keeps Database engine + Database peer + dedicated Notifier repo for
# cross-admin coordination.
oban_engine =
  case db_adapter do
    :sqlite -> Oban.Engines.Lite
    _ -> Oban.Engines.Basic
  end

oban_peer =
  case db_adapter do
    :sqlite -> Oban.Peers.Isolated
    _ -> Oban.Peers.Database
  end

oban_notifier =
  case db_adapter do
    :sqlite -> Oban.Notifiers.PG
    _ -> {Oban.Notifiers.Postgres, repo: Notifier}
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
#   execution_pruning      — daily sweep, batched deletes; 1 is enough
#   cluster_reconciliation — one job per cluster every 6h; 1 is enough
#   self_updates           — rare, triggered manually; 1 is fine
#   event_broker           — async broker publish with retry; 2 keeps it snappy
#                          without hammering the broker with parallel calls
#   webhooks               — HTTP delivery to user-configured endpoints; 2
#                          mitigates head-of-line blocking when one receiver
#                          is slow (HTTP timeouts can run 10s+, much longer
#                          than broker publish latency)
config :edge_admin, Oban,
  engine: oban_engine,
  queues: [
    execution_creation: 2,
    execution_pruning: 1,
    cluster_reconciliation: 1,
    self_updates: 1,
    event_broker: 2,
    webhooks: 2
  ],
  # Oban needs a real Ecto.Repo (calls __adapter__/0, config/0, etc.) so we
  # hand it the impl module directly, not the dispatcher.
  repo: repo_impl,
  # Notifier and peer are adapter-dependent — see oban_notifier / oban_peer above.
  notifier: oban_notifier,
  peer: oban_peer,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Reconcile clusters and nodes between DB and Netmaker
       {cluster_reconciliation_schedule, EdgeAdmin.Nodes.Workers.ScheduleClusterReconciliationWorker},
       # Delete finalised command executions older than retention
       {execution_pruning_schedule, EdgeAdmin.Commands.Workers.PruneExecutionsWorker}
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
  admin_max_wireguard_peers: get_env!("ADMIN_MAX_WIREGUARD_PEERS", :positive_integer),
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
  execution_pruning_enabled: execution_pruning_enabled,
  execution_pruning_schedule: execution_pruning_schedule,
  execution_retention_days: execution_retention_days,
  vpn_config_sync_schedule: vpn_config_sync_schedule,
  cluster_reconciliation_enabled: get_env("CLUSTER_RECONCILIATION_ENABLED", :boolean, true),
  cluster_reconciliation_schedule: cluster_reconciliation_schedule,
  zombie_admin_cleanup_schedule: zombie_admin_cleanup_schedule,
  zombie_admin_checkin_threshold_minutes: zombie_admin_checkin_threshold_minutes,
  # === Admin-cluster membership startup ===
  # Per-step timeout for membership join waits (Netmaker host registration,
  # netclient network join). Pre-flight + bounded waits replace the silent hang
  # that used to occur when CIDR was exhausted; tune up for slow Netmaker.
  join_timeout_seconds: get_env("MEMBERSHIP_JOIN_TIMEOUT_SECONDS", :integer, 60),
  # === VPN Sync Configuration ===
  # Disable periodic VPN config sync on severely resource-starved machines (default: true)
  vpn_config_sync_enabled: get_env("VPN_CONFIG_SYNC_ENABLED", :boolean, true),
  # Delete unrecognized hosts from cluster networks during reconciliation (default: true).
  evict_rogue_hosts: get_env("EVICT_ROGUE_HOSTS", :boolean, true),
  # === HTTP Request Timeouts (admin → agent) ===
  # Health checks run every minute across all owned nodes — keep tight; geo-friendly.
  health_check_timeout: get_env("HEALTH_CHECK_TIMEOUT_MS", :integer, 5_000),
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

# =============================================================================
# Event delivery — applies to both broker and webhook channels
# =============================================================================
# CORE_NAME stamps every envelope with the publishing instance's identity.
# EVENT_DELIVERY_MAX_AGE_SECONDS caps how long a delivery worker will keep
# retrying a single event. WEBHOOK_MAX_ATTEMPTS sets the per-event retry
# budget. WEBHOOK_ALLOW_PRIVATE_IPS opts out of SSRF protection for homelab
# / dev where webhook receivers legitimately live on RFC1918 ranges.
config :edge_admin,
  core_name: get_env("CORE_NAME", :string, "default"),
  event_delivery_max_age_seconds: get_env("EVENT_DELIVERY_MAX_AGE_SECONDS", :integer, 3600),
  webhook_max_attempts: get_env("WEBHOOK_MAX_ATTEMPTS", :integer, 3),
  webhook_allow_private_ips: get_env("WEBHOOK_ALLOW_PRIVATE_IPS", :boolean, false)

config :nexmaker,
  base_url: get_env!("NETMAKER_API_URL"),
  master_key: get_env!("NETMAKER_MASTER_KEY")

# Disable memsup (memory supervisor) from :os_mon
# We use PromEx + Prometheus for memory monitoring instead.
# memsup causes false alarms on Linux systems due to not understanding
# that cached memory is reclaimable (looks at MemFree instead of MemAvailable).
config :os_mon,
  start_memsup: false

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENVIRONMENT_NAME"),
  client: EdgeAdmin.Sentry.ReqClient,
  before_send: {EdgeAdmin.Sentry, :before_send}

# =============================================================================
# Event Broker
# =============================================================================
# Disabled by default; publish calls are no-ops. Enable with EVENT_BROKER_ENABLED=true,
# pick one EVENT_BROKER_ADAPTER, and set the adapter's vars (see deploy/.../.envs/.edge_admin
# for the per-adapter env var lists). Endpoint vars use _URLS (plural) for adapters that
# take a cluster list (NATS, Kafka) and _URL (singular) for single-endpoint adapters
# (RabbitMQ, Redis, MQTT). Managed-service adapters (AWS SNS, Google Pub/Sub) have no
# endpoint var — auth + region/project envs locate the service.
if get_env("EVENT_BROKER_ENABLED", :boolean, false) do
  event_broker_adapter =
    case get_env!("EVENT_BROKER_ADAPTER") do
      "nats" ->
        :nats

      "kafka" ->
        :kafka

      "amqp091" ->
        :rabbitmq

      "rabbitmq" ->
        :rabbitmq

      "redis" ->
        :redis

      "mqtt" ->
        :mqtt

      "aws_sns" ->
        :aws_sns

      "google_pubsub" ->
        :google_pubsub

      other ->
        raise "Unknown EVENT_BROKER_ADAPTER=#{other} — valid values: nats, kafka, amqp091 (alias: rabbitmq), redis, mqtt, aws_sns, google_pubsub"
    end

  config :edge_admin,
    event_broker_enabled: true,
    event_broker_adapter: event_broker_adapter

  case event_broker_adapter do
    :nats ->
      # NATS — gnat's ConnectionSupervisor accepts a list of {host, port} pairs
      # and rotates through them on reconnect (lib/gnat/connection_supervisor.ex).
      # EVENT_BROKER_NATS_URLS: comma-separated list of "nats://host:port".
      urls =
        "EVENT_BROKER_NATS_URLS"
        |> get_env!()
        |> String.split(",")
        |> Enum.map(&String.trim/1)

      config :edge_admin, :event_broker_nats,
        urls: urls,
        jetstream: get_env("EVENT_BROKER_NATS_JETSTREAM", :boolean, false),
        token: get_env("EVENT_BROKER_NATS_TOKEN"),
        username: get_env("EVENT_BROKER_NATS_USERNAME"),
        password: get_env("EVENT_BROKER_NATS_PASSWORD"),
        nkey_seed: get_env("EVENT_BROKER_NATS_NKEY_SEED"),
        jwt: get_env("EVENT_BROKER_NATS_JWT")

    :rabbitmq ->
      # RabbitMQ — amqp lib accepts a single URI string. Cluster failover is
      # handled broker-side (single hostname behind a load balancer or VIP).
      # Embed credentials directly: amqp://user:pass@host:port.
      config :edge_admin, :event_broker_rabbitmq,
        url: "EVENT_BROKER_RABBITMQ_URL" |> get_env!() |> String.trim(),
        ssl: get_env("EVENT_BROKER_RABBITMQ_SSL", :boolean, false)

    :kafka ->
      # Kafka — brod takes [endpoint()] for cluster discovery via metadata.
      # EVENT_BROKER_KAFKA_URLS: comma-separated "host:port" list (no scheme).
      brokers =
        "EVENT_BROKER_KAFKA_URLS"
        |> get_env!()
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

    :redis ->
      # Redis — redix takes a single URI string. Sentinel cluster mode exists
      # but uses a different keyword API (not the URI form), so we expose only
      # the single-URL path here. Credentials can be embedded:
      # redis://:password@host:port (Redis auth) or
      # redis://username:password@host:port (Redis 6+ ACL).
      config :edge_admin, :event_broker_redis,
        url: "EVENT_BROKER_REDIS_URL" |> get_env!() |> String.trim(),
        ssl: get_env("EVENT_BROKER_REDIS_SSL", :boolean, false)

    :mqtt ->
      # MQTT — single host:port endpoint. emqtt accepts a fallback list, but
      # this adapter uses a single endpoint to match the typical operator
      # mental model (one broker hostname behind any clustering).
      [host, port_str] =
        "EVENT_BROKER_MQTT_URL"
        |> get_env!()
        |> String.trim()
        |> String.split(":")

      mqtt_qos =
        case get_env("EVENT_BROKER_MQTT_QOS", :string, "1") do
          "0" -> 0
          "1" -> 1
          "2" -> 2
          other -> raise "Invalid EVENT_BROKER_MQTT_QOS=#{other} — valid values: 0, 1, 2"
        end

      config :edge_admin, :event_broker_mqtt,
        host: host,
        port: String.to_integer(port_str),
        qos: mqtt_qos,
        # Auth — mutually exclusive (JWT precedence over username/password):
        jwt: get_env("EVENT_BROKER_MQTT_JWT"),
        username: get_env("EVENT_BROKER_MQTT_USERNAME"),
        password: get_env("EVENT_BROKER_MQTT_PASSWORD"),
        # TLS:
        ssl: get_env("EVENT_BROKER_MQTT_SSL", :boolean, false),
        cacert_file: get_env("EVENT_BROKER_MQTT_CACERT_FILE"),
        client_cert_file: get_env("EVENT_BROKER_MQTT_CLIENT_CERT_FILE"),
        client_key_file: get_env("EVENT_BROKER_MQTT_CLIENT_KEY_FILE")

    :aws_sns ->
      # AWS SNS is a managed service — no EVENT_BROKER_URLS, no broker-server endpoint.
      # The adapter publishes via the AWS SNS API. Topics must be pre-provisioned in
      # the AWS account (Console / CLI / Terraform); the adapter constructs ARNs from
      # the configured prefix. Auth uses the AWS standard chain: env vars / shared
      # credentials file / instance profile / IAM role assumption — handled by ex_aws.
      # An optional EVENT_BROKER_AWS_SNS_ENDPOINT_URL override points at a non-AWS
      # endpoint (LocalStack) for testing; never set in production.
      aws_sns_region = get_env!("EVENT_BROKER_AWS_SNS_REGION")
      aws_sns_topic_arn_prefix = get_env!("EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX")

      # Configure ex_aws's :sns service with our region + endpoint override.
      # ex_aws resolves credentials independently from its own AWS_ACCESS_KEY_ID /
      # AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN env vars + instance metadata —
      # we don't pass them through here.
      sns_config = [region: aws_sns_region]

      sns_config =
        case get_env("EVENT_BROKER_AWS_SNS_ENDPOINT_URL") do
          nil ->
            sns_config

          endpoint ->
            uri = URI.parse(endpoint)

            sns_config ++
              [
                scheme: "#{uri.scheme}://",
                host: uri.host,
                port: uri.port
              ]
        end

      config :edge_admin, :event_broker_aws_sns,
        region: aws_sns_region,
        topic_arn_prefix: aws_sns_topic_arn_prefix,
        endpoint_url: get_env("EVENT_BROKER_AWS_SNS_ENDPOINT_URL")

      config :ex_aws, :http_client, ExAws.Request.Req
      config :ex_aws, :sns, sns_config

    :google_pubsub ->
      # Topics pre-provisioned in the operator's GCP project. Auth is the standard
      # GCP chain via goth. Emulator handling lives entirely here: setting
      # EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST flips base_url + auth so the
      # adapter has no concept of "emulator".
      base_url =
        case get_env("EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST") do
          nil -> "https://pubsub.googleapis.com"
          host -> "http://" <> host
        end

      auth =
        case get_env("EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST") do
          nil -> :goth
          _ -> :none
        end

      config :edge_admin, :event_broker_google_pubsub,
        project: get_env!("EVENT_BROKER_GOOGLE_PUBSUB_PROJECT"),
        topic_id_prefix: get_env("EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX", :string, ""),
        base_url: base_url,
        auth: auth
  end
end
