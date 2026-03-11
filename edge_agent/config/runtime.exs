# edge_agent/config/runtime.exs
import Config
import EdgeAgent.Config

# Optional environment variables with defaults
config :edge_agent, EdgeAgent.Repo,
  database: get_env("DB_PATH", :string, "/app/data/agent/edge_agent.db"),
  pool_size: get_env("DB_POOL_SIZE", :integer, 3)

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean, false) == true do
  config :edge_agent, EdgeAgentWeb.Endpoint, server: true
end

config :edge_agent, EdgeAgentWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env("API_PORT", :integer, 44_000)
  ],
  # Generate ephemeral secret_key_base (agent is stateless API, no sessions)
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48))

config :edge_agent,
  ssh_port: get_env("SSH_PORT", :integer, 40_022),
  host_metrics_port: get_env("HOST_METRICS_PORT", :integer, 49_100),
  wireguard_metrics_port: get_env("WIREGUARD_METRICS_PORT", :integer, 49_586),
  agent_wireguard_port: get_env("AGENT_WIREGUARD_PORT", :integer, nil),
  http_proxy_port: get_env("HTTP_PROXY_PORT", :integer, 43_128),
  socks5_proxy_port: get_env("SOCKS5_PROXY_PORT", :integer, 41_080),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 44_000),
  use_random_id: get_env("USE_RANDOM_ID", :boolean, false),
  enrollment_key: get_env("ENROLLMENT_KEY", :string, nil),
  public_enrollment_key_url: get_env("PUBLIC_ENROLLMENT_KEY_URL", :string, nil),
  public_enrollment_key_path: get_env("PUBLIC_ENROLLMENT_KEY_PATH", :string, nil),
  self_update_enabled: get_env("SELF_UPDATE_ENABLED", :boolean, false),
  watchtower_url: get_env("WATCHTOWER_URL", :string, ""),
  watchtower_http_api_token: get_env("WATCHTOWER_HTTP_API_TOKEN", :string, ""),
  proxy_blocked_ports: get_env("PROXY_BLOCKED_PORTS", :list, []),
  proxy_custom_blocked_hosts: get_env("PROXY_CUSTOM_BLOCKED_HOSTS", :list, []),
  proxy_custom_allowed_hosts: get_env("PROXY_CUSTOM_ALLOWED_HOSTS", :list, []),
  # HTTP request timeouts for admin communication (in milliseconds)
  http_receive_timeout: get_env("HTTP_RECEIVE_TIMEOUT_MS", :integer, 30_000),
  http_connect_timeout: get_env("HTTP_CONNECT_TIMEOUT_MS", :integer, 20_000),
  # VPN connection verification timeout (in seconds)
  vpn_ready_timeout_seconds: get_env("VPN_READY_TIMEOUT_SECONDS", :integer, 30),
  # Authentication toggles
  agent_metrics_auth_enabled: get_env("AGENT_METRICS_AUTH_ENABLED", :boolean, true),
  proxy_servers_auth_enabled: get_env("PROXY_SERVERS_AUTH_ENABLED", :boolean, true)
