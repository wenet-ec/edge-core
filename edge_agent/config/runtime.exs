# edge_agent/config/runtime.exs
import Config
import EdgeAgent.Config

# Optional environment variables with defaults
data_dir = get_env("DATA_DIR", :string, "/app/data")

config :edge_agent, EdgeAgent.Repo,
  database: "#{data_dir}/agent/edge_agent.db",
  pool_size: get_env("DB_POOL_SIZE", :integer, 10),
  busy_timeout: 5_000,
  queue_target: 100,
  queue_interval: 2_000

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean, false) == true do
  config :edge_agent, EdgeAgentWeb.Endpoint, server: true
end

api_port = get_env("API_PORT", :integer, 44_000)

# =============================================================================
# Background Job Schedules
# =============================================================================
enqueue_executions_schedule = get_env("ENQUEUE_EXECUTIONS_SCHEDULE", :string, "* * * * *")
report_executions_schedule = get_env("REPORT_EXECUTIONS_SCHEDULE", :string, "* * * * *")
sync_executions_schedule = get_env("SYNC_EXECUTIONS_SCHEDULE", :string, "*/2 * * * *")
report_health_check_schedule = get_env("REPORT_HEALTH_CHECK_SCHEDULE", :string, "*/2 * * * *")
discover_admins_schedule = get_env("DISCOVER_ADMINS_SCHEDULE", :string, "*/3 * * * *")
check_self_update_schedule = get_env("CHECK_SELF_UPDATE_SCHEDULE", :string, "0 */2 * * *")
push_metrics_schedule = get_env("PUSH_METRICS_SCHEDULE", :string, "*/2 * * * *")
pull_vpn_config_schedule = get_env("PULL_VPN_CONFIG_SCHEDULE", :string, "0 0 * * *")

config :edge_agent, EdgeAgentWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: api_port
  ],
  # Generate ephemeral secret_key_base (agent is stateless API, no sessions)
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48))

config :edge_agent, Oban,
  engine: Oban.Engines.Lite,
  repo: EdgeAgent.Repo,
  queues: [
    enqueue_executions: 1,
    execute_command: [limit: 10],
    report_executions: 1,
    sync_executions: 1,
    report_health_check: 1,
    discover_admins: 1,
    check_self_update: 1,
    push_metrics: 1,
    pull_vpn_config: 1
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Enqueue pending command executions
       {enqueue_executions_schedule, EdgeAgent.Commands.Workers.EnqueueExecutionWorker},
       # Report completed executions to admin (safety net)
       {report_executions_schedule, EdgeAgent.Commands.Workers.ReportExecutionWorker},
       # Sync unprocessed executions from admin (HTTP fallback mode)
       {sync_executions_schedule, EdgeAgent.Commands.Workers.SyncUnprocessedExecutionWorker},
       # Report node health to admin (HTTP fallback mode)
       {report_health_check_schedule, EdgeAgent.EdgeClusters.Workers.ReportHealthCheckWorker},
       # Probe VPN for admin peers
       {discover_admins_schedule, EdgeAgent.EdgeClusters.Workers.DiscoverAdminWorker},
       # Poll admin for self-update requests (HTTP fallback mode)
       {check_self_update_schedule, EdgeAgent.SelfUpdates.Workers.CheckSelfUpdateWorker},
       # Push metrics to admin (HTTP fallback mode)
       {push_metrics_schedule, EdgeAgent.Metrics.Workers.PushMetricsWorker},
       # Pull full VPN config from Netmaker (safety net for MQTT message loss / daemon-restart DNS loss)
       {pull_vpn_config_schedule, EdgeAgent.Vpn.Workers.PullVpnConfigWorker}
     ]},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 86_400}
  ]

# Proxy server per-operation timeouts (in milliseconds)
config :edge_agent, :proxy_timeouts,
  connection: get_env("PROXY_CONNECTION_TIMEOUT_MS", :integer, 2_000),
  read: get_env("PROXY_READ_TIMEOUT_MS", :integer, 10_000),
  recv: get_env("PROXY_RECV_TIMEOUT_MS", :integer, 300_000),
  tunnel_total: get_env("PROXY_TUNNEL_TOTAL_TIMEOUT_MS", :integer, 21_600_000),
  drain_grace: get_env("PROXY_DRAIN_GRACE_TIMEOUT_MS", :integer, 30_000)

config :edge_agent,
  proxy_num_acceptors: get_env("PROXY_NUM_ACCEPTORS", :integer, 100)

if get_env("SELF_UPDATE_ENABLED", :boolean, false) do
  config :edge_agent,
    self_update_enabled: true,
    watchtower_url: get_env!("WATCHTOWER_URL"),
    watchtower_http_api_token: get_env("WATCHTOWER_HTTP_API_TOKEN", :string, "")
else
  config :edge_agent,
    self_update_enabled: false,
    watchtower_url: "",
    watchtower_http_api_token: ""
end

config :edge_agent,
  api_port: api_port,
  ssh_port: get_env("SSH_PORT", :integer, 40_022),
  ssh_system_dir: "#{data_dir}/ssh",
  ssh_user_dir: "#{data_dir}/ssh/users",
  host_metrics_port: get_env("HOST_METRICS_PORT", :integer, 49_100),
  wireguard_metrics_port: get_env("WIREGUARD_METRICS_PORT", :integer, 49_586),
  agent_wireguard_port: get_env("AGENT_WIREGUARD_PORT", :integer, nil),
  http_proxy_port: get_env("HTTP_PROXY_PORT", :integer, 43_128),
  socks5_proxy_port: get_env("SOCKS5_PROXY_PORT", :integer, 41_080),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 44_000),
  aliases: get_env("ALIASES", :list, []),
  use_random_id: get_env("USE_RANDOM_ID", :boolean, false),
  enrollment_key: get_env("ENROLLMENT_KEY", :string, nil),
  public_enrollment_key_url: get_env("PUBLIC_ENROLLMENT_KEY_URL", :string, nil),
  public_enrollment_key_path: get_env("PUBLIC_ENROLLMENT_KEY_PATH", :string, nil),
  proxy_blocked_ports: get_env("PROXY_BLOCKED_PORTS", :list, []),
  proxy_custom_blocked_hosts: get_env("PROXY_CUSTOM_BLOCKED_HOSTS", :list, []),
  proxy_custom_allowed_hosts: get_env("PROXY_CUSTOM_ALLOWED_HOSTS", :list, []),
  # === HTTP Request Timeouts (agent → admin) ===
  # All regular admin API calls: registration, command acks, health reporting, metrics push.
  admin_call_timeout: get_env("ADMIN_CALL_TIMEOUT_MS", :integer, 10_000),
  # Admin discovery probing — short, probing many peers in parallel.
  # Bounds wall-clock cost of one parallel pass; tuned for geo-distributed VPN paths.
  admin_discovery_timeout: get_env("ADMIN_DISCOVERY_TIMEOUT_MS", :integer, 5_000),
  # VPN connection verification timeout (in seconds)
  vpn_ready_timeout_seconds: get_env("VPN_READY_TIMEOUT_SECONDS", :integer, 30),
  # Authentication toggles
  agent_metrics_auth_enabled: get_env("AGENT_METRICS_AUTH_ENABLED", :boolean, true),
  proxy_servers_auth_enabled: get_env("PROXY_SERVERS_AUTH_ENABLED", :boolean, true),
  # VPN config pull toggle — disable on resource-starved machines where netclient pull
  # causes disruptive interface resets. MQTT retained messages provide eventual consistency.
  pull_vpn_config_enabled: get_env("PULL_VPN_CONFIG_ENABLED", :boolean, true),
  # DERP map refresh interval at steady state. On startup the cache warms up with a short
  # interval (5 s) that doubles each miss until this value is reached.
  derp_map_refresh_interval_ms: get_env("DERP_MAP_REFRESH_INTERVAL_MS", :integer, to_timeout(minute: 5))
