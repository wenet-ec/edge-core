# edge_agent/config/config.exs
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

version = Mix.Project.config()[:version]

config :edge_agent, EdgeAgentWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: EdgeAgent.PubSub,
  render_errors: [
    formats: [json: EdgeAgentWeb.Controllers.ErrorJSON],
    layout: false
  ]

config :edge_agent, EdgeAgentWeb.Plugs.Security, allow_unsafe_scripts: false

config :edge_agent,
  ecto_repos: [EdgeAgent.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :edge_agent,
  ecto_repos: [EdgeAgent.Repo],
  version: version

# erlexec runs its port program (and therefore its child shells) as root
# inside the agent container. The port program refuses to start as root
# unless it's told to via -user / -limit_users; we restrict it to root only.
config :erlexec,
  root: true,
  user: ~c"root",
  limit_users: [~c"root"]

config :mdns_lite,
  if_monitor: MdnsLite.InetMonitor,
  hosts: [:hostname],
  ttl: 120

# Import environment configuration
config :phoenix, :filter_parameters, [
  "password",
  "api_token",
  "proxy_password",
  "enrollment_token",
  "enrollment_key",
  "secret",
  "token"
]

config :phoenix, :json_library, Jason

import_config "#{Mix.env()}.exs"
