# edge_admin/config/test.exs
import Config

alias Ecto.Adapters.SQL.Sandbox
alias EdgeAdmin.Repo.Postgres
alias EdgeAdmin.Repo.SQLite

defmodule TestEnvironment do
  @moduledoc false
  @database_name_suffix "_test"

  def get_database_name do
    db_name = System.get_env("DB_NAME")

    if is_nil(db_name) do
      raise "DB_NAME environment variable is required for tests"
    end

    if String.ends_with?(db_name, @database_name_suffix) do
      db_name
    else
      raise "Expected database name to end with '#{@database_name_suffix}', got: #{db_name}"
    end
  end
end

# DB_ADAPTER selects the test repo impl. Postgres mode runs against the
# real edge_admin_db. SQLite mode runs against a DB file under
# SQLITE_DB_PATH (default /app/data/edge_admin_test.db, mounted on the
# local_edge_admin_test_data volume in cloud.lite.yml).
test_db_adapter =
  case System.get_env("DB_ADAPTER", "postgres") do
    "sqlite" -> :sqlite
    _ -> :postgres
  end

test_repo_impl =
  case test_db_adapter do
    :sqlite -> SQLite
    :postgres -> Postgres
  end

# This config is to output keys instead of translated message in test
config :edge_admin, EdgeAdmin.Gettext, priv: "priv/null", interpolation: EdgeAdmin.GettextInterpolation

# Disable Quantum during tests:
config :edge_admin, EdgeAdmin.LocalScheduler, jobs: []
config :edge_admin, EdgeAdminWeb.Endpoint, server: false

# Disable Oban during tests:
config :edge_admin, Oban, testing: :manual

case test_db_adapter do
  :postgres ->
    config :edge_admin, Postgres,
      username: System.get_env("DB_USER"),
      password: System.get_env("DB_PASSWORD"),
      hostname: System.get_env("DB_HOST"),
      database: "#{TestEnvironment.get_database_name()}#{System.get_env("MIX_TEST_PARTITION")}",
      port: String.to_integer(System.get_env("DB_PORT")),
      pool: Sandbox,
      pool_size: System.schedulers_online() * 2

  :sqlite ->
    config :edge_admin, SQLite,
      database: System.get_env("SQLITE_DB_PATH", "/app/data/edge_admin_test.db"),
      pool: Sandbox,
      pool_size: System.schedulers_online() * 2
end

config :edge_admin, :db_adapter, test_db_adapter

# Use mock for Metadata module in tests
config :edge_admin, :metadata_module, EdgeAdmin.MetadataMock

# Use mock for Nodes module in tests
config :edge_admin, :nodes_module, EdgeAdmin.NodesMock
config :edge_admin, :repo_impl, test_repo_impl
config :edge_admin, ecto_repos: [test_repo_impl]

# Disable admin clustering during tests
config :edge_admin,
  run_bootstrap: false,
  admin_id: "test123456",
  admin_name: "admin-test123456",
  admin_cluster_name: "admin-cluster-test",
  admin_max_wireguard_peers: 100,
  vpn_cluster_cookie: :test_cookie,
  admin_discovery_port: 44_000,
  netmaker_default_domain: "nm.internal"

config :logger, level: :warning
