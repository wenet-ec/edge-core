# edge_agent/lib/edge_agent/release.ex
defmodule EdgeAgent.Release do
  @moduledoc """
  Release tasks for migrating and rolling back the agent's SQLite database.

  Invoked from compose entrypoints in production builds where the Elixir
  toolchain isn't available; uses `Application.load/1` instead of starting
  the full app, so migrations don't trigger Bootstrap or open VPN/SSH.
  """

  alias Ecto.Migrator

  @app :edge_agent

  @doc """
  Runs all pending migrations on every Repo registered in `:ecto_repos`
  (currently just `EdgeAgent.Repo`).
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls a single Repo back to the supplied migration version.
  """
  def rollback(repo, version) do
    load_app()

    {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
