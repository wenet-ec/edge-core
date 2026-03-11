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
    enqueue_executions: 1,
    execute_command: [limit: 10],
    report_executions: 1,
    sync_executions: 1,
    report_health_check: 1,
    discover_admins: 1,
    check_self_update: 1,
    push_metrics: 1,
    pull_vpn_config: 1
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Every minute to enqueue pending executions
       {"* * * * *", EdgeAgent.Commands.Workers.EnqueueExecutionWorker},
       # Every minute for reporting (safety net)
       {"* * * * *", EdgeAgent.Commands.Workers.ReportExecutionWorker},
       # Every 2 minutes to sync unprocessed executions (HTTP fallback mode)
       {"*/2 * * * *", EdgeAgent.Commands.Workers.SyncUnprocessedExecutionWorker},
       # Every 2 minutes to report health check (HTTP fallback mode)
       {"*/2 * * * *", EdgeAgent.EdgeClusters.Workers.ReportHealthCheckWorker},
       # Every 3 minutes for admin discovery
       {"*/3 * * * *", EdgeAgent.EdgeClusters.Workers.DiscoverAdminWorker},
       # Every 2 hours to check for self-updates (HTTP fallback mode)
       {"0 */2 * * *", EdgeAgent.SelfUpdates.Workers.CheckSelfUpdateWorker},
       # Every 2 minutes to push metrics (HTTP fallback mode)
       {"*/2 * * * *", EdgeAgent.Metrics.Workers.PushMetricsWorker},
       # Every 6 hours to pull VPN config from Netmaker (safety net for MQTT message loss)
       {"0 */6 * * *", EdgeAgent.Vpn.Workers.PullVpnConfigWorker}
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
