# edge_admin/config/dev.exs
import Config

config :edge_admin, EdgeAdmin.PromEx,
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, EdgeAdminWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 44000],
  code_reloader: true,
  debug_errors: true,
  check_origin: false,
  live_reload: [
    patterns: [
      ~r{priv/gettext/.*$},
      ~r{lib/edge_admin_web/.*(ee?x)$}
    ]
  ]

config :edge_admin, EdgeAdminWeb.Plugs.Security, allow_unsafe_scripts: true

# Enable dev routes for dashboard and mailbox
config :edge_admin, dev_routes: true

config :file_system,
  backend: :fs_inotify,
  executable_file: System.find_executable("inotifywait") || "/usr/bin/inotifywait"

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Disable OpenApiSpex caching in development for live spec updates
config :open_api_spex, :cache_adapter, OpenApiSpex.Plug.NoneCache

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
