# edge_admin/config/config.exs
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

import Config

version = Mix.Project.config()[:version]

config :edge_admin, EdgeAdmin.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

config :edge_admin, EdgeAdmin.Repo.Postgres,
  priv: "priv/repo",
  start_apps_before_migration: [:ssl]

# Connection-only repo for Oban.Notifiers.Postgres — not in :ecto_repos so
# migrations don't run against it. Bypasses PgBouncer in prod.
config :edge_admin, EdgeAdmin.Repo.Postgres.Notifier,
  priv: "priv/repo",
  start_apps_before_migration: [:ssl]

config :edge_admin, EdgeAdmin.Repo.SQLite,
  migration_lock: nil,
  priv: "priv/repo",
  start_apps_before_migration: [:ssl]

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

config :flop, repo: EdgeAdmin.Repo

config :phoenix, :filter_parameters, [
  "password",
  "authorization",
  "proxy-authorization",
  "x-api-key",
  "api_token",
  "proxy_password",
  "enrollment_token",
  "enrollment_key",
  "secret",
  "token",
  "headers"
]

config :phoenix, :json_library, JSON

config :sentry,
  root_source_code_path: File.cwd!(),
  release: version

# Syn event handler bridge — forwards admin join/leave events to Metadata for
# immediate recomputation instead of waiting for the 60s periodic scheduler.
config :syn, event_handler: EdgeAdmin.Admins.SynEventHandler

import_config "#{Mix.env()}.exs"
