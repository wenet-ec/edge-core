# edge_admin/lib/edge_admin/release.ex
defmodule EdgeAdmin.Release do
  @moduledoc """
  Release tasks for Edge Admin.

  Provides Mix-like tasks that can be run in production releases:
  - Database migrations
  - Netmaker superadmin bootstrap
  - Default cluster creation
  """

  alias Ecto.Migrator
  alias EdgeAdmin.Vpn

  require Logger

  @app :edge_admin

  # =============================================================================
  # Config Helpers
  # =============================================================================

  defp netmaker_superadmin_username do
    Application.get_env(:edge_admin, :netmaker_superadmin_username)
  end

  defp netmaker_superadmin_password do
    Application.get_env(:edge_admin, :netmaker_superadmin_password)
  end

  defp default_cluster_name do
    Application.get_env(:edge_admin, :default_cluster_name)
  end

  defp default_cluster_subnet do
    Application.get_env(:edge_admin, :default_cluster_subnet)
  end

  # =============================================================================
  # Database Migrations
  # =============================================================================

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

  # =============================================================================
  # Netmaker Superadmin Bootstrap
  # =============================================================================

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
    start_http_client()

    Logger.info("Checking if Netmaker superadmin exists...")

    case Vpn.check_superadmin() do
      {:ok, true} ->
        Logger.info("Netmaker superadmin already exists, skipping creation")
        :ok

      {:ok, false} ->
        Logger.info("No superadmin found, creating superadmin: #{netmaker_superadmin_username()}")
        do_create_superadmin()

      {:error, reason} ->
        Logger.error("Failed to check superadmin status: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp do_create_superadmin do
    attrs = %{
      username: netmaker_superadmin_username(),
      password: netmaker_superadmin_password()
    }

    case Vpn.create_superadmin(attrs) do
      {:ok, _user} ->
        Logger.info("Successfully created Netmaker superadmin: #{netmaker_superadmin_username()}")
        :ok

      {:error, {:http_error, status, body}} ->
        Logger.error("Failed to create superadmin (HTTP #{status}): #{body}")
        System.halt(1)

      {:error, reason} ->
        Logger.error("Failed to create superadmin: #{inspect(reason)}")
        System.halt(1)
    end
  end

  # =============================================================================
  # Default Cluster Bootstrap
  # =============================================================================

  @doc """
  Creates default cluster if configured.

  Reads configuration from Application config (configured in runtime.exs):
  - `:default_cluster_name` - Name for the default cluster (optional)
  - `:default_cluster_subnet` - IPv4 CIDR range (optional, auto-generates if not provided)

  This task is idempotent and optional:
  - Skips if `default_cluster_name` is not configured
  - Skips if cluster with that name already exists
  - Auto-generates subnet if not provided

  ## Exit codes
    - 0: Success (created or already exists or skipped)
    - 1: Failure (validation error, API error)
  """
  def create_default_cluster do
    load_app()
    start_http_client()
    start_repo()
    start_phoenix_pubsub()

    case default_cluster_name() do
      nil ->
        Logger.info("Skipping default cluster creation: DEFAULT_CLUSTER_NAME not set")
        :ok

      name ->
        Logger.info("Checking if default cluster exists: #{name}")

        case EdgeAdmin.Nodes.get_cluster(name) do
          nil ->
            Logger.info("Default cluster not found, creating: #{name}")
            do_create_cluster(name)

          _cluster ->
            Logger.info("Default cluster already exists, skipping: #{name}")
            :ok
        end
    end
  end

  defp do_create_cluster(cluster_name) do
    # Build attrs - only include subnet if provided
    attrs =
      case default_cluster_subnet() do
        nil -> %{"name" => cluster_name}
        subnet -> %{"name" => cluster_name, "ipv4_range" => subnet}
      end

    case EdgeAdmin.Nodes.create_cluster(attrs) do
      {:ok, cluster} ->
        Logger.info(
          "Successfully created default cluster: #{cluster.name} (#{cluster.ipv4_range})"
        )
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        Logger.error("Failed to create default cluster: #{inspect(errors)}")
        System.halt(1)

      {:error, reason} ->
        Logger.error("Failed to create default cluster: #{inspect(reason)}")
        System.halt(1)
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp start_http_client do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:req)
  end

  defp start_repo do
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto)
    Application.ensure_all_started(:ecto_sql)

    for repo <- repos() do
      {:ok, _} = repo.start_link()
    end
  end

  defp start_phoenix_pubsub do
    Application.ensure_all_started(:phoenix_pubsub)

    children = [
      {Phoenix.PubSub, name: EdgeAdmin.PubSub}
    ]

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  end
end
