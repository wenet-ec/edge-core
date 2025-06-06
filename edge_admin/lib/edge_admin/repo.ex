# edge_admin/lib/edge_admin/repo.ex
defmodule EdgeAdmin.Repo do
  use Ecto.Repo,
    adapter: Ecto.Adapters.Postgres,
    otp_app: :edge_admin

  @doc """
  Dynamically loads the repository url from the
  DATABASE_URL environment variable.
  """
  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, Application.get_env(:edge_admin, __MODULE__)[:url])}
  end
end
