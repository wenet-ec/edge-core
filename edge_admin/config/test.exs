# edge_admin/config/test.exs
import Config

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

# This config is to output keys instead of translated message in test
config :edge_admin, EdgeAdmin.Gettext, priv: "priv/null", interpolation: EdgeAdmin.GettextInterpolation

# Disable Quantum during tests:
config :edge_admin, EdgeAdmin.LocalScheduler, jobs: []

config :edge_admin, EdgeAdmin.Repo,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PASSWORD"),
  hostname: System.get_env("DB_HOST"),
  database: "#{TestEnvironment.get_database_name()}#{System.get_env("MIX_TEST_PARTITION")}",
  port: String.to_integer(System.get_env("DB_PORT")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :edge_admin, EdgeAdminWeb.Endpoint, server: false

# Disable Oban during tests:
config :edge_admin, Oban, testing: :manual

# Use mock for Nodes module in tests
config :edge_admin, :nodes_module, EdgeAdmin.NodesMock

# Disable admin clustering during tests
config :edge_admin,
  run_bootstrap: false,
  admin_id: "test123456",
  admin_name: "admin-test123456",
  admin_cluster_name: "admin-cluster-test",
  admin_max_capacity: 100,
  erlang_cookie: :test_cookie,
  admin_discovery_port: 44_000,
  netmaker_default_domain: "nm.internal"

config :logger, level: :warning
