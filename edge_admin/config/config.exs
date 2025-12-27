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

config :edge_admin, EdgeAdmin.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, EdgeAdmin.Repo, start_apps_before_migration: [:ssl]

config :edge_admin, EdgeAdminWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: EdgeAdmin.PubSub,
  render_errors: [
    formats: [json: EdgeAdminWeb.Controllers.ErrorJSON],
    layout: false
  ]

config :edge_admin, EdgeAdminWeb.Plugs.Security, allow_unsafe_scripts: false

config :edge_admin,
  ecto_repos: [EdgeAdmin.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  version: version

config :edge_admin,
  ecto_repos: [EdgeAdmin.Repo],
  version: version

# Proxy server timeouts (in milliseconds)
config :edge_admin, :proxy_timeouts,
  connection: 5_000,
  handshake: 10_000,
  read: 10_000

config :flop, repo: EdgeAdmin.Repo

config :phoenix, :json_library, Jason

# Import environment configuration
config :sentry,
  root_source_code_path: File.cwd!(),
  release: version

import_config "#{Mix.env()}.exs"
