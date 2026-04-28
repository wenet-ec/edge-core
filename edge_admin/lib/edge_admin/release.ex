# edge_admin/lib/edge_admin/release.ex
defmodule EdgeAdmin.Release do
  @moduledoc """
  Release tasks for Edge Admin.
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

  defp default_cluster_node_limit do
    Application.get_env(:edge_admin, :default_cluster_node_limit)
  end

  # =============================================================================
  # Database Migrations
  # =============================================================================

  def migrate do
    boot([])

    for repo <- repos() do
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    boot([])

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
    boot([:http])

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

      {:error, :already_exists} ->
        Logger.info("Netmaker superadmin already exists (likely created by a peer replica), skipping")
        :ok

      {:error, :service_unavailable} ->
        Logger.error("Failed to create superadmin: Netmaker service unavailable")
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
    boot([:http, :repo])

    case default_cluster_name() do
      nil ->
        Logger.info("Skipping default cluster creation: DEFAULT_CLUSTER_NAME not set")
        :ok

      name ->
        Logger.info("Checking if default cluster exists: #{name}")

        case EdgeAdmin.Nodes.get_cluster(name) do
          {:ok, _cluster} ->
            Logger.info("Default cluster already exists, skipping: #{name}")
            :ok

          {:error, :not_found} ->
            Logger.info("Default cluster not found, creating: #{name}")
            do_create_cluster(name)
        end
    end
  end

  defp do_create_cluster(cluster_name) do
    attrs =
      %{name: cluster_name}
      |> maybe_put(:ipv4_range, default_cluster_subnet())
      |> maybe_put(:node_limit, default_cluster_node_limit())

    case EdgeAdmin.Nodes.create_cluster(attrs) do
      {:ok, cluster} ->
        Logger.info("Successfully created default cluster: #{cluster.name} (#{cluster.ipv4_range})")

        :ok

      {:error, {:conflict, reason}} ->
        Logger.warning("Default cluster creation skipped: #{reason}")
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
  # Boot Helpers
  # =============================================================================

  # Loads the app and starts the runtime dependencies a release task needs.
  # `parts` selects optional capability groups; `:logger` and `:sentry` are
  # always started so failures are observable in production.
  defp boot(parts) do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(:logger)
    {:ok, _} = Application.ensure_all_started(:sentry)

    Enum.each(parts, &start_part/1)
  end

  defp start_part(:http) do
    {:ok, _} = Application.ensure_all_started(:req)
  end

  defp start_part(:repo) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    for repo <- repos() do
      {:ok, _} = repo.start_link(pool_size: 2)
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
