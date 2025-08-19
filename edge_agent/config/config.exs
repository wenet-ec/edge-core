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
    formats: [json: EdgeAgentWeb.ErrorJSON],
    layout: false
  ]

config :edge_agent, EdgeAgentWeb.Plugs.Security, allow_unsafe_scripts: false

config :edge_agent, Oban,
  engine: Oban.Engines.Lite,
  repo: EdgeAgent.Repo,
  queues: [
    vpn: 2,
    command_execution: 1,
    command_reporting: 1,
    command_scheduling: 1
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", EdgeAgent.VPN.Workers.ConnectivityCheckingWorker},
       {"* * * * *", EdgeAgent.VPN.Workers.AutoReconnectingWorker},
       # Every minute for faster reporting
       {"* * * * *", EdgeAgent.Commands.Workers.CommandReportScheduler},
       # Every 2 minutes safety net
       {"*/2 * * * *", EdgeAgent.Commands.Workers.CommandExecutionScheduler}
     ]}
  ]

config :edge_agent,
  ecto_repos: [EdgeAgent.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :edge_agent,
  ecto_repos: [EdgeAgent.Repo],
  version: version

config :logger, backends: [:console]

config :phoenix, :json_library, Jason

# Import environment configuration
import_config "#{Mix.env()}.exs"
