# edge_agent/config/runtime.exs
import Config
import EdgeAgent.Config

config :edge_agent, EdgeAgent.Repo,
  database: get_env!("DATABASE_PATH"),
  pool_size: get_env!("DATABASE_POOL_SIZE", :integer)

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean) == true do
  config :edge_agent, EdgeAgentWeb.Endpoint, server: true
end

config :edge_agent, Corsica, origins: get_env("CORS_ALLOWED_ORIGINS", :cors)

config :edge_agent, EdgeAgentWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env!("PORT", :integer)
  ],
  secret_key_base: get_env!("SECRET_KEY_BASE"),
  session_key: get_env!("SESSION_KEY"),
  session_signing_salt: get_env!("SESSION_SIGNING_SALT"),
  live_view: [signing_salt: get_env!("SESSION_SIGNING_SALT")]

config :edge_agent,
  basic_auth: [
    username: get_env("BASIC_AUTH_USERNAME"),
    password: get_env("BASIC_AUTH_PASSWORD")
  ]
