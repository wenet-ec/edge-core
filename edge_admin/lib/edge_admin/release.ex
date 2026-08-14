# edge_admin/lib/edge_admin/release.ex
defmodule EdgeAdmin.Release do
  @moduledoc """
  Release tasks for Edge Admin. Each task boots only what it needs and is safe
  to run on every container start (idempotent where applicable).

  Wired into `deploy/{local,production}/compose/edge_admin/start`:

    * `migrate/0` — run pending Ecto migrations on the active repo
    * `rollback/1` — roll back to a target migration version
    * `rotate_encryption_key/0` — re-encrypt rows through old → new encryption key
      (gated on the four `ROTATE_*` env vars; logs skip and exits clean
      otherwise)
    * `bootstrap_edge_vpn_admin/0` — bootstrap the Edge VPN UI admin
    * `create_default_cluster/0` — pre-create the cluster named by
      `DEFAULT_CLUSTER_NAME` (skipped if unset)
  """

  alias Cloak.Ciphers.AES.GCM
  alias Ecto.Migrator
  alias EdgeAdmin.Encryption.SchemaRegistry
  alias EdgeAdmin.Vpn

  require Logger

  @app :edge_admin
  # PostgreSQL advisory-lock namespace for the outer migration bootstrap lock.
  # This intentionally differs from Ecto's own migration lock: it is acquired
  # before Ecto initializes `schema_migrations`, closing that first-table race.
  @migration_bootstrap_lock_namespace 116_203
  @migration_bootstrap_lock_key 1
  @edge_vpn_admin_bootstrap_max_retries 6
  @edge_vpn_admin_bootstrap_base_delay_ms 250
  @edge_vpn_admin_bootstrap_max_delay_ms 2_000

  defp edge_vpn_bootstrap_username do
    Application.get_env(:edge_admin, :edge_vpn_bootstrap_username)
  end

  defp edge_vpn_bootstrap_password do
    Application.get_env(:edge_admin, :edge_vpn_bootstrap_password)
  end

  defp default_cluster_name do
    Application.get_env(:edge_admin, :default_cluster_name)
  end

  defp default_cluster_v4_subnet do
    Application.get_env(:edge_admin, :default_cluster_v4_subnet)
  end

  defp default_cluster_v6_subnet do
    Application.get_env(:edge_admin, :default_cluster_v6_subnet)
  end

  defp default_cluster_node_limit do
    Application.get_env(:edge_admin, :default_cluster_node_limit)
  end

  def migrate do
    boot([])

    for repo <- repos() do
      {:ok, _, _} =
        Migrator.with_repo(repo, fn repo ->
          with_migration_bootstrap_lock(repo, fn -> Migrator.run(repo, :up, all: true) end)
        end)
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

  @doc """
  Creates Edge VPN admin user if doesn't exist.

  Reads credentials from Application config (configured in runtime.exs):
  - `:edge_vpn_bootstrap_username` - Username for the bootstrap account
  - `:edge_vpn_bootstrap_password` - Password for the bootstrap account

  This task is idempotent and safe to run concurrently on every Admin replica.
  Edge VPN's check-then-create API is not atomic, so an ambiguous create failure
  is followed by a bounded, backoff-delayed re-check. This lets a replica observe
  a superadmin created by a peer instead of failing its container startup.

  ## Exit codes
    - 0: Success (created or already exists)
    - 1: Failure (API error)
  """
  def bootstrap_edge_vpn_admin do
    boot([:http])

    Logger.info("Checking if Edge VPN admin exists...")

    case ensure_edge_vpn_admin(@edge_vpn_admin_bootstrap_max_retries) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to bootstrap Edge VPN admin: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp ensure_edge_vpn_admin(retries_left) do
    case Vpn.check_superadmin() do
      {:ok, true} ->
        Logger.info("Edge VPN admin already exists, skipping creation")
        :ok

      {:ok, false} ->
        Logger.info("No superadmin found, creating superadmin: #{edge_vpn_bootstrap_username()}")
        bootstrap_edge_vpn_admin_or_retry(retries_left)

      {:error, reason} ->
        retry_edge_vpn_admin_bootstrap(:check, reason, retries_left)
    end
  end

  defp bootstrap_edge_vpn_admin_or_retry(retries_left) do
    attrs = %{
      username: edge_vpn_bootstrap_username(),
      password: edge_vpn_bootstrap_password()
    }

    case Vpn.create_superadmin(attrs) do
      {:ok, _user} ->
        Logger.info("Successfully created Edge VPN admin: #{edge_vpn_bootstrap_username()}")
        :ok

      {:error, :already_exists} ->
        Logger.info("Edge VPN admin already exists (likely created by a peer replica), skipping")
        :ok

      {:error, reason} ->
        # A concurrent peer can create the user after our initial check. The
        # Edge VPN API may report that outcome as either its documented
        # `superadmin user already exists` response or a database constraint
        # error, so re-check before treating it as a startup failure.
        retry_edge_vpn_admin_bootstrap(:create, reason, retries_left)
    end
  end

  defp retry_edge_vpn_admin_bootstrap(_operation, reason, 0), do: {:error, reason}

  defp retry_edge_vpn_admin_bootstrap(operation, reason, retries_left) do
    attempt = @edge_vpn_admin_bootstrap_max_retries - retries_left + 1
    delay = edge_vpn_admin_bootstrap_delay(attempt)

    Logger.warning(
      "Edge VPN admin #{operation} failed: #{inspect(reason)}. " <>
        "Re-checking in #{delay}ms (#{retries_left} retries remaining)."
    )

    Process.sleep(delay)
    ensure_edge_vpn_admin(retries_left - 1)
  end

  defp edge_vpn_admin_bootstrap_delay(attempt) do
    min(
      @edge_vpn_admin_bootstrap_base_delay_ms * Integer.pow(2, attempt - 1),
      @edge_vpn_admin_bootstrap_max_delay_ms
    )
  end

  @doc """
  Creates default cluster if configured.

  Reads configuration from Application config (configured in runtime.exs):
  - `:default_cluster_name` - Name for the default cluster (optional)
  - `:default_cluster_v4_subnet` - IPv4 CIDR range (optional, auto-generates if not provided)
  - `:default_cluster_v6_subnet` - IPv6 ULA /64 (optional, auto-generates if not provided)

  This task is idempotent and optional:
  - Skips if `default_cluster_name` is not configured
  - Skips if cluster with that name already exists
  - Auto-generates either address family if not provided

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
      |> maybe_put(:ipv4_range, default_cluster_v4_subnet())
      |> maybe_put(:ipv6_range, default_cluster_v6_subnet())
      |> maybe_put(:node_limit, default_cluster_node_limit())

    case EdgeAdmin.Nodes.create_cluster(attrs) do
      {:ok, cluster} ->
        Logger.info(
          "Successfully created default cluster: #{cluster.name} (#{cluster.ipv4_range}, #{cluster.ipv6_range})"
        )

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

  @doc """
  Rotates the encryption-at-rest key.

  Idempotent — safe to run multiple times. Reads four env vars; if any is
  missing, logs skip and returns `:ok` without touching the DB. When all four
  are present, re-encrypts every row in every schema returned by
  `EdgeAdmin.Encryption.SchemaRegistry.schemas/0` through `old → new`.

  Required env vars (all four, or none):
    - `ROTATE_OLD_ENCRYPTION_KEY`  — old key, base64-encoded 32 bytes
    - `ROTATE_OLD_ENCRYPTION_TAG`  — old tag (e.g. "AES.GCM.V1")
    - `ROTATE_NEW_ENCRYPTION_KEY`  — new key, base64-encoded 32 bytes
    - `ROTATE_NEW_ENCRYPTION_TAG`  — new tag (e.g. "AES.GCM.V2")

  Idempotent because the per-row tag prefix tells the migrator which
  cipher decrypted each row; a row already encrypted under the new tag is
  decrypted with the new key and re-encrypted with the new key (wasteful
  but correct). A mid-rotation interruption can be resumed by re-running.

  After the task completes successfully, operators update `ENCRYPTION_KEY` /
  `ENCRYPTION_TAG` to the new values and remove the four `ROTATE_*` env vars on
  the next deploy. There is no time pressure — running the task again with
  the old `ROTATE_*` values would still succeed but do nothing useful.

  ## Exit codes
    - 0: rotation completed, or skipped because envs missing
    - 1: rotation attempted but failed (key decode error, DB error, etc.)
  """
  def rotate_encryption_key do
    boot([:repo])

    case read_rotation_envs() do
      :skip ->
        :ok

      {:ok, params} ->
        Logger.info("Starting encryption key rotation: #{params.old_tag} → #{params.new_tag}")

        Application.put_env(:edge_admin, EdgeAdmin.Encryption,
          ciphers: [
            default: {GCM, tag: params.new_tag, key: params.new_key},
            retired: {GCM, tag: params.old_tag, key: params.old_key}
          ]
        )

        {:ok, _} = Application.ensure_all_started(:cloak_ecto)
        {:ok, _} = EdgeAdmin.Encryption.start_link()

        do_rotate(SchemaRegistry.schemas())
    end
  end

  defp read_rotation_envs do
    envs = %{
      old_key: System.get_env("ROTATE_OLD_ENCRYPTION_KEY"),
      old_tag: System.get_env("ROTATE_OLD_ENCRYPTION_TAG"),
      new_key: System.get_env("ROTATE_NEW_ENCRYPTION_KEY"),
      new_tag: System.get_env("ROTATE_NEW_ENCRYPTION_TAG")
    }

    missing = for {k, nil} <- envs, do: k

    cond do
      length(missing) == 4 ->
        Logger.info("Skip: no ROTATE_* env vars set")
        :skip

      missing == [] ->
        decode_rotation_keys(envs)

      true ->
        present = envs |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Enum.map(&elem(&1, 0))

        Logger.info(
          "Skip: incomplete ROTATE_* envs " <>
            "(present: #{inspect(present)}, missing: #{inspect(missing)}). " <>
            "All four are required to rotate."
        )

        :skip
    end
  end

  defp decode_rotation_keys(envs) do
    with {:ok, old_key} <- decode_key(envs.old_key, "ROTATE_OLD_ENCRYPTION_KEY"),
         {:ok, new_key} <- decode_key(envs.new_key, "ROTATE_NEW_ENCRYPTION_KEY") do
      {:ok, %{old_key: old_key, old_tag: envs.old_tag, new_key: new_key, new_tag: envs.new_tag}}
    end
  end

  defp decode_key(value, name) do
    case Base.decode64(value) do
      {:ok, bytes} when byte_size(bytes) == 32 ->
        {:ok, bytes}

      {:ok, bytes} ->
        Logger.error(
          "#{name} decoded to #{byte_size(bytes)} bytes — must be 32 (AES-256). " <>
            "Generate with: openssl rand -base64 32"
        )

        System.halt(1)

      :error ->
        Logger.error("#{name} is not valid base64")
        System.halt(1)
    end
  end

  defp do_rotate(schemas) do
    [repo] = repos()

    Enum.each(schemas, fn schema ->
      Logger.info("Rotating schema: #{inspect(schema)}")
      Cloak.Ecto.Migrator.migrate(repo, schema)
    end)

    Logger.info("Encryption key rotation complete.")
    :ok
  end

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

  # Ecto creates `schema_migrations` before its configured migration lock can
  # protect migration execution. On a brand-new PostgreSQL database, multiple
  # Admin replicas can therefore race while PostgreSQL creates that table's
  # implicit row type. Hold an outer, session-scoped lock first so only one
  # replica can reach Ecto's bootstrap path at a time.
  #
  # The lock lives on the Repo checkout connection. PostgreSQL releases it if
  # this process or its connection dies; the explicit unlock covers success and
  # ordinary migration failures. This requires the same direct/session-pinned
  # PostgreSQL connection contract as Ecto's `:pg_advisory_lock`.
  defp with_migration_bootstrap_lock(repo, fun) do
    case Application.fetch_env!(@app, :db_adapter) do
      :postgres ->
        Logger.info("Waiting for PostgreSQL migration bootstrap lock...")

        repo.checkout(fn ->
          repo.query!(
            "SELECT pg_advisory_lock($1::integer, $2::integer)",
            [@migration_bootstrap_lock_namespace, @migration_bootstrap_lock_key]
          )

          Logger.info("Acquired PostgreSQL migration bootstrap lock")

          try do
            fun.()
          after
            _ =
              repo.query(
                "SELECT pg_advisory_unlock($1::integer, $2::integer)",
                [@migration_bootstrap_lock_namespace, @migration_bootstrap_lock_key]
              )
          end
        end)

      :sqlite ->
        fun.()
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
