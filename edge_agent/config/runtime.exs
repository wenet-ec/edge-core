# edge_agent/config/runtime.exs
import Config
import EdgeAgent.Config

# Optional environment variables with defaults
config :edge_agent, EdgeAgent.Repo,
  database: get_env("DATABASE_PATH", :string, "/app/data/edge_agent.db"),
  pool_size: get_env("DATABASE_POOL_SIZE", :integer, 3)

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
  http_proxy_port: get_env("HTTP_PROXY_PORT", :integer, 43_128),
  socks5_proxy_port: get_env("SOCKS5_PROXY_PORT", :integer, 41_080),
  admin_discovery_port: get_env("ADMIN_DISCOVERY_PORT", :integer, 44_000),
  netmaker_default_domain: get_env("NETMAKER_DEFAULT_DOMAIN", :string, "nm.internal"),
  use_random_id: get_env("USE_RANDOM_ID", :boolean, false),
  enrollment_key: get_env("ENROLLMENT_KEY", :string, nil),
  public_enrollment_key_url: get_env("PUBLIC_ENROLLMENT_KEY_URL", :string, nil),
  public_enrollment_key_path: get_env("PUBLIC_ENROLLMENT_KEY_PATH", :string, nil)
