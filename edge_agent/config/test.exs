# edge_agent/config/test.exs
import Config

defmodule TestEnvironment do
  @moduledoc false
  @database_name_suffix "_test.db"

  def get_database_path do
    path = System.get_env("DATABASE_PATH")

    if is_nil(path) || String.ends_with?(path, @database_name_suffix) do
      path
    else
      raise "Expected database path to end with '#{@database_name_suffix}', got: #{path}"
    end
  end
end

# This config is to output keys instead of translated message in test
config :edge_agent, EdgeAgent.Gettext, priv: "priv/null", interpolation: EdgeAgent.GettextInterpolation

config :edge_agent, EdgeAgent.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  database: TestEnvironment.get_database_path()

config :edge_agent, EdgeAgentWeb.Endpoint, server: false

# Disable Oban during tests:
config :edge_agent, Oban, testing: :manual

config :logger, level: :warning
