# edge_admin/lib/edge_admin/release.ex
defmodule EdgeAdmin.Release do
  @moduledoc false
  alias Ecto.Migrator
  require Logger

  @app :edge_admin

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates Netmaker superadmin user if doesn't exist.

  Reads credentials from Application config (configured in runtime.exs):
  - `:netmaker_superadmin_username` - Username for the superadmin
  - `:netmaker_superadmin_password` - Password for the superadmin

  This task is idempotent - it will skip creation if a superadmin already exists.

  ## Exit codes
    - 0: Success (created or already exists)
    - 1: Failure (API error)
  """
  def create_netmaker_superadmin do
    load_app()
    start_dependencies()

    username = Application.get_env(:edge_admin, :netmaker_superadmin_username)
    password = Application.get_env(:edge_admin, :netmaker_superadmin_password)

    create_superadmin_if_needed(username, password)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_dependencies do
    # Start only the minimum dependencies needed for HTTP requests
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:httpoison)
  end

  defp create_superadmin_if_needed(username, password) do
    Logger.info("Checking if Netmaker superadmin exists...")

    case Nexmaker.Api.Superadmin.check() do
      {:ok, true} ->
        Logger.info("Netmaker superadmin already exists, skipping creation")
        :ok

      {:ok, false} ->
        Logger.info("No superadmin found, creating superadmin: #{username}")
        create_superadmin(username, password)

      {:error, reason} ->
        Logger.error("Failed to check superadmin status: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp create_superadmin(username, password) do
    attrs = %{
      username: username,
      password: password
    }

    case Nexmaker.Api.Superadmin.create(attrs) do
      {:ok, _user} ->
        Logger.info("Successfully created Netmaker superadmin: #{username}")
        :ok

      {:error, {:http_error, status, body}} ->
        Logger.error("Failed to create superadmin (HTTP #{status}): #{body}")
        System.halt(1)

      {:error, reason} ->
        Logger.error("Failed to create superadmin: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
