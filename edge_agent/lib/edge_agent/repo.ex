# edge_agent/lib/edge_agent/repo.ex
defmodule EdgeAgent.Repo do
  use Ecto.Repo,
    adapter: Ecto.Adapters.SQLite3,
    otp_app: :edge_agent

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, Application.get_env(:edge_agent, __MODULE__)[:url])}
  end
end
