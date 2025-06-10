# edge_admin/config/runtime.exs
import Config
import EdgeAdmin.Config

config :edge_admin, EdgeAdmin.Repo,
  url: get_env!("DATABASE_URL"),
  ssl: get_env("DATABASE_SSL", :boolean),
  pool_size: get_env!("DATABASE_POOL_SIZE", :integer),
  socket_options: if(get_env("DATABASE_IPV6", :boolean), do: [:inet6], else: [])

# NOTE: Only set `server` to `true` if `PHX_SERVER` is present. We cannot set
# it to `false` otherwise because `mix phx.server` will stop working without it.
if get_env("PHX_SERVER", :boolean) == true do
  config :edge_admin, EdgeAdminWeb.Endpoint, server: true
end

config :edge_admin, Corsica, origins: get_env("CORS_ALLOWED_ORIGINS", :cors)
config :edge_admin, EdgeAdmin.TelemetryUI, share_key: get_env("TELEMETRY_UI_SHARE_KEY")

config :edge_admin, EdgeAdminWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: get_env!("PORT", :integer)
  ],
  secret_key_base: get_env!("SECRET_KEY_BASE"),
  session_key: get_env!("SESSION_KEY"),
  session_signing_salt: get_env!("SESSION_SIGNING_SALT"),
  live_view: [signing_salt: get_env!("SESSION_SIGNING_SALT")]

config :edge_admin,
  basic_auth: [
    username: get_env("BASIC_AUTH_USERNAME"),
    password: get_env("BASIC_AUTH_PASSWORD")
  ]

config :sentry,
  dsn: get_env("SENTRY_DSN"),
  environment_name: get_env("SENTRY_ENVIRONMENT_NAME")
