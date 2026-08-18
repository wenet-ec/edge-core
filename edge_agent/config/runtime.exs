# edge_agent/config/runtime.exs
import Config
import EdgeAgent.Config

alias EdgeAgent.LocalScheduler.Tasks

data_dir = get_env("DATA_DIR", :string, "/app/data")
recovery_key = get_env("RECOVERY_KEY", :string)
command_execution_concurrency = get_env("COMMAND_EXECUTION_CONCURRENCY", :integer, 4)

config :edge_agent, EdgeAgent.Repo,
  database: "#{data_dir}/agent/edge_agent.db",
  pool_size: get_env("DB_POOL_SIZE", :integer, 5),
  busy_timeout: 30_000,
  queue_target: 100,
  queue_interval: 2_000

# Only set `server` to `true` when `PHX_SERVER` is present. Setting it to
# `false` here prevents `mix phx.server` from starting the endpoint.
if get_env("PHX_SERVER", :boolean, false) == true do
  config :edge_agent, EdgeAgentWeb.Endpoint, server: true
end

api_port = get_env("AGENT_API_PORT", :integer, 44_000)
agent_metrics_port = get_env("AGENT_METRICS_PORT", :integer, nil)

if is_integer(agent_metrics_port) and agent_metrics_port == api_port do
  raise "AGENT_METRICS_PORT must differ from AGENT_API_PORT when dedicated metrics are enabled"
end

# Background Job Schedules
enqueue_executions_schedule = get_env("ENQUEUE_EXECUTIONS_SCHEDULE", :string, "* * * * *")
report_executions_schedule = get_env("REPORT_EXECUTIONS_SCHEDULE", :string, "* * * * *")
sync_executions_schedule = get_env("SYNC_EXECUTIONS_SCHEDULE", :string, "*/2 * * * *")
report_health_check_schedule = get_env("REPORT_HEALTH_CHECK_SCHEDULE", :string, "*/2 * * * *")
push_diagnostics_schedule = get_env("PUSH_DIAGNOSTICS_SCHEDULE", :string, "*/2 * * * *")
discover_admins_schedule = get_env("DISCOVER_ADMINS_SCHEDULE", :string, "*/3 * * * *")
refresh_settings_config_schedule = get_env("REFRESH_SETTINGS_CONFIG_SCHEDULE", :string, "*/5 * * * *")
check_self_update_schedule = get_env("CHECK_SELF_UPDATE_SCHEDULE", :string, "0 */2 * * *")
push_metrics_schedule = get_env("PUSH_METRICS_SCHEDULE", :string, "*/2 * * * *")
pull_vpn_config_schedule = get_env("PULL_VPN_CONFIG_SCHEDULE", :string, "0 0 * * *")

# In-process cron for stateless, idempotent housekeeping. Avoids writing an
# `oban_jobs` row per tick on the agent's SQLite.
config :edge_agent, EdgeAgent.LocalScheduler,
  jobs: [
    discover_admins: [
      schedule: discover_admins_schedule,
      task: {Tasks, :discover_admins, []}
    ],
    refresh_settings_config: [
      schedule: refresh_settings_config_schedule,
      task: {Tasks, :refresh_settings_config, []}
    ],
    report_health_check: [
      schedule: report_health_check_schedule,
      task: {Tasks, :report_health_check, []}
    ],
    push_diagnostics: [
      schedule: push_diagnostics_schedule,
      task: {Tasks, :push_diagnostics, []}
    ],
    sync_unprocessed_executions: [
      schedule: sync_executions_schedule,
      task: {Tasks, :sync_unprocessed_executions, []}
    ],
    push_metrics: [
      schedule: push_metrics_schedule,
      task: {Tasks, :push_metrics, []}
    ],
    check_self_update: [
      schedule: check_self_update_schedule,
      task: {Tasks, :check_self_update, []}
    ],
    pull_vpn_config: [
      schedule: pull_vpn_config_schedule,
      task: {Tasks, :pull_vpn_config, []}
    ]
  ]

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
    execute_command: [limit: command_execution_concurrency],
    report_executions: 1
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Enqueue pending command executions
       {enqueue_executions_schedule, EdgeAgent.Commands.Workers.EnqueueExecutionWorker},
       # Report completed executions to admin (safety net)
       {report_executions_schedule, EdgeAgent.Commands.Workers.ReportExecutionWorker}
     ]},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 3_600}
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
  recovery_key: recovery_key,
  agent_api_port: api_port,
  agent_metrics_port: agent_metrics_port || api_port,
  agent_metrics_dedicated: is_integer(agent_metrics_port),
  agent_ssh_port: get_env("AGENT_SSH_PORT", :integer, 40_022),
  ssh_system_dir: "#{data_dir}/ssh",
  ssh_user_dir: "#{data_dir}/ssh/users",
  agent_host_metrics_port: get_env("AGENT_HOST_METRICS_PORT", :integer, 49_100),
  agent_wireguard_metrics_port: get_env("AGENT_WIREGUARD_METRICS_PORT", :integer, 49_586),
  agent_wireguard_port: get_env("AGENT_WIREGUARD_PORT", :integer, nil),
  agent_http_proxy_port: get_env("AGENT_HTTP_PROXY_PORT", :integer, 43_128),
  agent_socks5_proxy_port: get_env("AGENT_SOCKS5_PROXY_PORT", :integer, 41_080),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 44_000),
  aliases: get_env("ALIASES", :list, []),
  enrollment_key: get_env("ENROLLMENT_KEY", :string, nil),
  public_enrollment_key_urls: get_env("PUBLIC_ENROLLMENT_KEY_URLS", :list, []),
  public_enrollment_key_paths: get_env("PUBLIC_ENROLLMENT_KEY_PATHS", :list, []),
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
  agent_proxy_auth_enabled: get_env("AGENT_PROXY_AUTH_ENABLED", :boolean, true),
  # VPN config pull toggle — disable on resource-starved machines where netclient pull
  # causes disruptive interface resets. MQTT retained messages provide eventual consistency.
  pull_vpn_config_enabled: get_env("PULL_VPN_CONFIG_ENABLED", :boolean, true),
  # DERP map refresh interval at steady state. On startup the cache warms up with a short
  # interval (5 s) that doubles each miss until this value is reached.
  derp_map_refresh_interval_ms: get_env("DERP_MAP_REFRESH_INTERVAL_MS", :integer, to_timeout(minute: 5))
