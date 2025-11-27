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

config :edge_agent, Corsica, origins: get_env("CORS_ALLOWED_ORIGINS", :cors, "*")

config :edge_agent, EdgeAgentWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env("API_PORT", :integer, 4000)
  ],
  secret_key_base: get_env("SECRET_KEY_BASE", :string, "default-secret-key-base-change-in-production"),
  session_key: get_env("SESSION_KEY", :string, "edge_agent"),
  session_signing_salt: get_env("SESSION_SIGNING_SALT", :string, "default-session-signing-salt"),
  live_view: [
    signing_salt: get_env("SESSION_SIGNING_SALT", :string, "default-session-signing-salt")
  ]

config :edge_agent,
  basic_auth: [
    username: get_env("BASIC_AUTH_USERNAME", :string, nil),
    password: get_env("BASIC_AUTH_PASSWORD", :string, nil)
  ]
