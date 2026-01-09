# edge_agent/config/config.exs
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

version = Mix.Project.config()[:version]

config :edge_agent, Corsica, allow_headers: :all
config :edge_agent, EdgeAgent.Gettext, default_locale: "en"

config :edge_agent, EdgeAgentWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: EdgeAgent.PubSub,
  render_errors: [
    formats: [json: EdgeAgentWeb.Controllers.ErrorJSON],
    layout: false
  ]

config :edge_agent, EdgeAgentWeb.Plugs.Security, allow_unsafe_scripts: false

config :edge_agent, Oban,
  engine: Oban.Engines.Lite,
  repo: EdgeAgent.Repo,
  queues: [
    execution_enqueue: 1,
    command_execution: [limit: 10],
    execution_report: 1,
    admin_discovery: 1,
    vpn_config_pull: 1,
    relayed_node: 1
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Every minute to enqueue pending executions
       {"* * * * *", EdgeAgent.Commands.Workers.ExecutionEnqueueWorker},
       # Every minute for reporting (safety net)
       {"* * * * *", EdgeAgent.Commands.Workers.ExecutionReportWorker},
       # Every 3 minutes to create relayed node
       {"*/3 * * * *", EdgeAgent.EdgeClusters.Workers.RegisterRelayedNodeWorker},
       # Every 5 minutes for admin discovery
       {"*/5 * * * *", EdgeAgent.EdgeClusters.Workers.AdminDiscoveryWorker},
       # Every 30 minutes to pull VPN config from Netmaker
       {"*/30 * * * *", EdgeAgent.Vpn.Workers.VpnConfigPullWorker}
     ]},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Pruner, max_age: 86_400}
  ]

# Proxy server timeouts (in milliseconds)
config :edge_agent, :proxy_timeouts,
  connection: 30_000,
  read: 10_000

config :edge_agent,
  ecto_repos: [EdgeAgent.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :edge_agent,
  ecto_repos: [EdgeAgent.Repo],
  version: version

config :phoenix, :json_library, Jason

# Import environment configuration
import_config "#{Mix.env()}.exs"
