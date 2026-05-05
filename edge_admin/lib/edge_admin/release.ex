# edge_admin/lib/edge_admin/release.ex
defmodule EdgeAdmin.Release do
  @moduledoc """
  Release tasks for Edge Admin.
  """

  alias Cloak.Ciphers.AES.GCM
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

  # The runtime-selected impl is always the single entry in :ecto_repos, so
  # callers don't pass a repo — DB_ADAPTER picks it. Invoke as:
  #
  #   bin/edge_admin eval 'EdgeAdmin.Release.rollback(20250101000001)'
  def rollback(version) do
    boot([])

    for repo <- repos() do
      {:ok, _, _} = Migrator.with_repo(repo, &Migrator.run(&1, :down, to: version))
    end
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
  # Cloak Key Rotation
  # =============================================================================

  @doc """
  Rotates the Cloak encryption key.

  Idempotent — safe to run multiple times. Reads four env vars; if any is
  missing, logs skip and returns `:ok` without touching the DB. When all four
  are present, re-encrypts every row in every schema returned by
  `EdgeAdmin.Vault.encrypted_schemas/0` through `old → new`.

  Required env vars (all four, or none):
    - `ROTATE_OLD_CLOAK_KEY`  — old key, base64-encoded 32 bytes
    - `ROTATE_OLD_CLOAK_TAG`  — old tag (e.g. "AES.GCM.V1")
    - `ROTATE_NEW_CLOAK_KEY`  — new key, base64-encoded 32 bytes
    - `ROTATE_NEW_CLOAK_TAG`  — new tag (e.g. "AES.GCM.V2")

  Idempotent because Cloak's per-row tag prefix tells the migrator which
  cipher decrypted each row; a row already encrypted under the new tag is
  decrypted with the new key and re-encrypted with the new key (wasteful
  but correct). A mid-rotation interruption can be resumed by re-running.

  After the task completes successfully, operators update `CLOAK_KEY` /
  `CLOAK_TAG` to the new values and remove the four `ROTATE_*` env vars on
  the next deploy. There is no time pressure — running the task again with
  the old `ROTATE_*` values would still succeed but do nothing useful.

  ## Exit codes
    - 0: rotation completed, or skipped because envs missing
    - 1: rotation attempted but failed (key decode error, DB error, etc.)
  """
  def rotate_cloak_key do
    boot([:repo])

    case read_rotation_envs() do
      :skip ->
        :ok

      {:ok, params} ->
        Logger.info("[CloakRotation] Starting rotation: #{params.old_tag} → #{params.new_tag}")

        Application.put_env(:edge_admin, EdgeAdmin.Vault,
          ciphers: [
            default: {GCM, tag: params.new_tag, key: params.new_key},
            retired: {GCM, tag: params.old_tag, key: params.old_key}
          ]
        )

        {:ok, _} = Application.ensure_all_started(:cloak_ecto)
        {:ok, _} = EdgeAdmin.Vault.start_link()

        do_rotate(EdgeAdmin.Vault.encrypted_schemas())
    end
  end

  defp read_rotation_envs do
    envs = %{
      old_key: System.get_env("ROTATE_OLD_CLOAK_KEY"),
      old_tag: System.get_env("ROTATE_OLD_CLOAK_TAG"),
      new_key: System.get_env("ROTATE_NEW_CLOAK_KEY"),
      new_tag: System.get_env("ROTATE_NEW_CLOAK_TAG")
    }

    missing = for {k, nil} <- envs, do: k

    cond do
      length(missing) == 4 ->
        Logger.info("[CloakRotation] Skip: no ROTATE_* env vars set")
        :skip

      missing == [] ->
        decode_rotation_keys(envs)

      true ->
        present = envs |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Enum.map(&elem(&1, 0))

        Logger.info(
          "[CloakRotation] Skip: incomplete ROTATE_* envs " <>
            "(present: #{inspect(present)}, missing: #{inspect(missing)}). " <>
            "All four are required to rotate."
        )

        :skip
    end
  end

  defp decode_rotation_keys(envs) do
    with {:ok, old_key} <- decode_key(envs.old_key, "ROTATE_OLD_CLOAK_KEY"),
         {:ok, new_key} <- decode_key(envs.new_key, "ROTATE_NEW_CLOAK_KEY") do
      {:ok, %{old_key: old_key, old_tag: envs.old_tag, new_key: new_key, new_tag: envs.new_tag}}
    end
  end

  defp decode_key(value, name) do
    case Base.decode64(value) do
      {:ok, bytes} when byte_size(bytes) == 32 ->
        {:ok, bytes}

      {:ok, bytes} ->
        Logger.error(
          "[CloakRotation] #{name} decoded to #{byte_size(bytes)} bytes — must be 32 (AES-256). " <>
            "Generate with: openssl rand -base64 32"
        )

        System.halt(1)

      :error ->
        Logger.error("[CloakRotation] #{name} is not valid base64")
        System.halt(1)
    end
  end

  defp do_rotate(schemas) do
    [repo] = repos()

    Enum.each(schemas, fn schema ->
      Logger.info("Rotating schema: #{inspect(schema)}")
      Cloak.Ecto.Migrator.migrate(repo, schema)
    end)

    Logger.info("Cloak Rotation complete.")
    :ok
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
    # Start ecto_sql plus the driver app the active adapter needs. ecto_sql
    # does not list postgrex/exqlite as required applications (drivers are
    # optional), so they must be started explicitly per adapter.
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(driver_app())

    for repo <- repos() do
      {:ok, _} = repo.start_link(pool_size: 2)
    end
  end

  defp driver_app do
    case Application.fetch_env!(@app, :db_adapter) do
      :sqlite -> :exqlite
      _ -> :postgrex
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
