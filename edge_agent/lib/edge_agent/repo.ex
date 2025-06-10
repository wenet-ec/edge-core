# edge_agent/lib/edge_agent/repo.ex
defmodule EdgeAgent.Repo do
  use Ecto.Repo,
    adapter: Ecto.Adapters.SQLite3,
    otp_app: :edge_agent
end
