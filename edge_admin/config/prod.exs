# config/prod.exs
import Config

config :edge_admin, EdgeAdminWeb.Endpoint, debug_errors: false

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: :info,
  metadata: ~w(request_id)a
