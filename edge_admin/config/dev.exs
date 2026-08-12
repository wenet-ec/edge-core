# edge_admin/config/dev.exs
import Config

config :edge_admin, EdgeAdmin.PromEx,
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, EdgeAdminWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 44_000],
  code_reloader: true,
  debug_errors: true,
  check_origin: false,
  live_reload: [
    patterns: [
      ~r{lib/edge_admin_web/.*(ee?x)$}
    ]
  ]

config :edge_admin, EdgeAdminWeb.Plugs.Security, allow_unsafe_scripts: true

# Phoenix-only development routes.
config :edge_admin, dev_routes: true

config :file_system,
  backend: :fs_inotify,
  executable_file: System.find_executable("inotifywait") || "/usr/bin/inotifywait"

# Keep development logs short.
config :logger, :console, format: "[$level] $message\n"

# Regenerate OpenAPI output on each request in development.
config :open_api_spex, :cache_adapter, OpenApiSpex.Plug.NoneCache

# Defer plug initialization for faster recompilation.
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
