# edge_agent/config/dev.exs
import Config

# Development-specific overrides only
config :edge_agent, EdgeAgent.Repo,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :edge_agent, EdgeAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  code_reloader: true,
  debug_errors: true,
  check_origin: false,
  live_reload: [
    patterns: [
      ~r{priv/gettext/.*$},
      ~r{lib/edge_agent_web/.*(ee?x)$}
    ]
  ]

config :edge_agent, EdgeAgentWeb.Plugs.Security, allow_unsafe_scripts: true

# Enable dev routes for dashboard and mailbox
config :edge_agent, dev_routes: true

config :file_system,
  backend: :fs_inotify,
  executable_file: System.find_executable("inotifywait") || "/usr/bin/inotifywait"

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
