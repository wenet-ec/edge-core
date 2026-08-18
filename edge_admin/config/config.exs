# edge_admin/config/config.exs
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

# Connection-only repo for Oban.Notifiers.Postgres. It stays out of :ecto_repos
# so migrations never run against the notifier connection.
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

# Internal password-hasher rotation list. The first hasher creates new hashes;
# retained hashers verify their own legacy hashes until those credentials have
# been upgraded on successful use or explicitly reset.
config :edge_admin, :password_hashers, [EdgeAdmin.PasswordHashers.Algorithms.Argon2]

config :edge_admin,
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  version: version

# The active Repo implementation is selected at runtime from DB_ADAPTER and
# configured in runtime.exs. Tests select their implementation in test.exs.

config :flop, repo: EdgeAdmin.Repo

config :phoenix, :filter_parameters, [
  "password",
  "authorization",
  "proxy-authorization",
  "x-api-key",
  "api_token",
  "proxy_password",
  "recovery_key",
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
config :syn, event_handler: EdgeAdmin.AdminClustering.SynEventHandler

import_config "#{Mix.env()}.exs"
