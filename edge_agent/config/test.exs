# edge_agent/config/test.exs
import Config

# Disable Quantum job firing during tests — the scheduler isn't started in the
# test supervision tree, but config is loaded module-wide; an empty jobs list
# keeps the LocalScheduler inert if it ever does get started.
config :edge_agent, EdgeAgent.LocalScheduler, jobs: []
config :edge_agent, EdgeAgent.Repo, pool: Ecto.Adapters.SQL.Sandbox
config :edge_agent, EdgeAgentWeb.Endpoint, server: false

# Disable Oban during tests:
config :edge_agent, Oban, testing: :manual
config :edge_agent, run_bootstrap: false

config :logger, level: :warning
