# edge_admin/config/config.exs
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

version = Mix.Project.config()[:version]

config :edge_admin, Corsica, allow_headers: :all
config :edge_admin, EdgeAdmin.Gettext, default_locale: "en"

config :edge_admin, EdgeAdmin.Repo,
  migration_primary_key: [type: :binary_id, default: {:fragment, "gen_random_uuid()"}],
  migration_timestamps: [type: :utc_datetime_usec],
  start_apps_before_migration: [:ssl]

config :edge_admin, EdgeAdminWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: EdgeAdmin.PubSub,
  render_errors: [
    formats: [json: EdgeAdminWeb.ErrorJSON],
    layout: false
  ]

config :edge_admin, EdgeAdminWeb.Plugs.Security, allow_unsafe_scripts: false

config :edge_admin, Oban,
  engine: Oban.Engines.Basic,
  queues: [vpn: 5],
  repo: EdgeAdmin.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Every minute - connectivity check
       {"* * * * *", EdgeAdmin.VPN.Workers.ConnectivityChecker},
       # Every 2 minutes - auto reconnection check
       {"*/2 * * * *", EdgeAdmin.VPN.Workers.AutoReconnector}
     ]}
  ]

config :edge_admin, :vpn, client: EdgeAdmin.VPN.Clients.Tailscale

config :edge_admin,
  ecto_repos: [EdgeAdmin.Repo],
  version: version

config :logger, backends: [:console, Sentry.LoggerBackend]

config :phoenix, :json_library, Jason

config :sentry,
  root_source_code_path: File.cwd!(),
  release: version

# Import environment configuration
import_config "#{Mix.env()}.exs"
