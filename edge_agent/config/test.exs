# edge_agent/config/test.exs
import Config

defmodule TestEnvironment do
  @moduledoc false
  @database_name_suffix "_test"

  def get_database_url do
    url = System.get_env("DATABASE_URL")

    if is_nil(url) || String.ends_with?(url, @database_name_suffix) do
      url
    else
      raise "Expected database URL to end with '#{@database_name_suffix}', got: #{url}"
    end
  end
end

# This config is to output keys instead of translated message in test
config :edge_agent, EdgeAgent.Gettext, priv: "priv/null", interpolation: EdgeAgent.GettextInterpolation

config :edge_agent, EdgeAgent.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  url: TestEnvironment.get_database_url()

config :edge_agent, EdgeAgentWeb.Endpoint, server: false

# Disable Oban during tests:
config :edge_agent, Oban, testing: :manual

config :logger, level: :warning
