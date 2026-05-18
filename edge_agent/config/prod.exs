# edge_agent/config/prod.exs
import Config

config :edge_agent, EdgeAgentWeb.Endpoint, debug_errors: false

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: :info,
  metadata: ~w(request_id mfa)a

# Force synchronous writes to the default :logger_std_h handler. The async
# queue (default sync_mode_qlen: 10) can drop init-time log bursts when
# stdout is briefly slow — e.g. during post-host-reboot container startup.
# Agent log volume is low enough that per-call sync latency is negligible.
config :logger, :default_handler, config: %{sync_mode_qlen: 0}
