# edge_agent/config/test.exs
import Config

# This config is to output keys instead of translated message in test
config :edge_agent, EdgeAgent.Gettext, priv: "priv/null", interpolation: EdgeAgent.GettextInterpolation
config :edge_agent, EdgeAgent.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :edge_agent, EdgeAgentWeb.Endpoint, server: false

# Disable Oban during tests:
config :edge_agent, Oban, testing: :manual
config :edge_agent, run_bootstrap: false

config :logger, level: :warning
