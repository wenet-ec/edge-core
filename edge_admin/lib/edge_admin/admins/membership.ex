# edge_admin/lib/edge_admin/admins/membership.ex
defmodule EdgeAdmin.Admins.Membership do
  @moduledoc """
  Establishes this admin's membership in the admin cluster.

  Runs as a one-shot GenServer during application startup. Its only job is to
  put this admin instance on the admin VPN, wire up Erlang distribution, and
  register with the syn group so peer admins can find it. Once this completes,
  the admin is a participating member of the cluster; until it does, the rest
  of the supervision tree is intentionally held back.

  ## Key Concepts

  - **Admin Cluster**: VPN network connecting all admin instances for HA coordination
  - **Erlang Distribution**: Enables inter-admin RPC, syn registry, and clustering
  - **Peer Discovery**: Finds other admins in the cluster via Netmaker API

  ## Responsibilities

  1. **VPN Network Join**
     - Join admin cluster VPN network
     - Create network if this is the first admin in the cluster
     - Obtain Netmaker host ID for this admin

  2. **Erlang Distribution**
     - Start distributed Erlang with configured cookie
     - Set node name based on admin DNS hostname
     - Enable inter-admin communication

  3. **Peer Discovery**
     - Query Netmaker for other admins in the cluster
     - Connect to peer Erlang nodes
     - Enable distributed syn registry

  4. **syn Initialization**
     - Join cluster_scope for Gateway registration
     - Enable cross-admin request routing

  ## Membership Sequence

  ```
  1. Ensure Netmaker superadmin exists
  2. Join admin cluster network (create if needed)
  3. Get Netmaker host ID
  4. Start Erlang distribution
  5. Discover peer admins via Netmaker API
  6. Connect to peer Erlang nodes
  7. Initialize syn registry
  ```

  ## Failure Handling

  Membership failures are **FATAL** and crash the supervision tree:
  - VPN join failure → Can't communicate with peers
  - Erlang distribution failure → Can't coordinate
  - syn initialization failure → Can't route requests

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:admin_id` - Random 12-char identifier (e.g., "7k3m9p2n")
  - `:admin_name` - Prefixed name (e.g., "admin-7k3m9p2n")
  - `:admin_cluster_name` - Shared cluster name (e.g., "admin-cluster-main")
  - `:admin_max_wireguard_peers` - WireGuard peer budget for this admin (e.g., 250).
    Counts both admin-mesh peers and edge-node peers. The metadata layer derives
    `edge_node_capacity = max_wireguard_peers - (total_admins - 1)` from this.
  - `:vpn_cluster_cookie` - Shared secret for Erlang distribution over the VPN cluster
  - `:admin_cluster_subnet` - Optional subnet (auto-generates if missing)

  ## Examples

      # Membership runs automatically on application start
      # Success: Application continues
      # Failure: Application crashes with detailed error

      # Check if membership has been established
      iex> Membership.initialized?()
      true
  """

  use GenServer

  alias EdgeAdmin.Admins.Discovery
  alias EdgeAdmin.Vpn

  require Logger

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Starts the Membership GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if admin-cluster membership has been successfully established.
  Used by health checks.
  """
  def initialized? do
    case Process.whereis(__MODULE__) do
      nil ->
        false

      pid ->
        try do
          GenServer.call(pid, :initialized?, 1000)
        catch
          :exit, _ -> false
        end
    end
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    Logger.info("Membership startup beginning...")

    case do_establish_membership() do
      :ok ->
        Logger.info("Admin-cluster membership established")
        {:ok, %{status: :complete, initialized: true}}

      {:error, reason} ->
        Logger.error("Failed to establish admin-cluster membership: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  # =============================================================================
  # Config Helpers
  # =============================================================================

  defp admin_name, do: Application.get_env(:edge_admin, :admin_name)
  defp admin_cluster_name, do: Application.get_env(:edge_admin, :admin_cluster_name)
  defp admin_cluster_subnet, do: Application.get_env(:edge_admin, :admin_cluster_subnet)
  defp max_wireguard_peers, do: Application.get_env(:edge_admin, :admin_max_wireguard_peers)
  defp vpn_cluster_cookie, do: Application.get_env(:edge_admin, :vpn_cluster_cookie)
  defp admin_wireguard_port, do: Application.get_env(:edge_admin, :admin_wireguard_port)

  # =============================================================================
  # Membership Flow
  # =============================================================================

  defp do_establish_membership do
    start_time = System.monotonic_time(:millisecond)

    result =
      with :ok <- step_1_join_vpn(),
           :ok <- step_2_start_erlang_distribution(),
           :ok <- step_3_initialize_syn(),
           :ok <- step_4_discover_peers() do
        Logger.info("All membership steps completed")
        :ok
      else
        {:error, reason} = error ->
          Logger.error("Membership step failed: #{inspect(reason)}")
          error
      end

    duration = System.monotonic_time(:millisecond) - start_time

    status =
      case result do
        :ok -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_admin, :membership, :complete],
      %{duration: duration, count: 1, total: 1},
      %{status: status}
    )

    result
  end

  # =============================================================================
  # Step 1: VPN Network Join
  # =============================================================================

  # Bounded waits prevent silent hangs when Netmaker/netclient never produce a
  # result we expect. The total per-step budget is `:join_timeout_seconds`
  # (env: `MEMBERSHIP_JOIN_TIMEOUT_SECONDS`, default 60s). Polling cadence is
  # held at 2s — operators tune the budget, not the cadence.
  @join_retry_delay_ms 2_000

  defp join_max_attempts do
    timeout_seconds = Application.get_env(:edge_admin, :join_timeout_seconds, 60)
    max(1, div(timeout_seconds * 1_000, @join_retry_delay_ms))
  end

  defp step_1_join_vpn do
    network_name = admin_cluster_name()
    admin_name = admin_name()
    Logger.info("Step 1: Joining VPN network #{network_name}")

    start_time = System.monotonic_time(:millisecond)

    # Build join options, adding static port if configured
    join_opts = build_join_opts(admin_name)

    max_attempts = join_max_attempts()

    result =
      with :ok <- ensure_network_exists(network_name),
           :ok <- check_capacity(network_name),
           {:ok, token} <- Vpn.get_default_enrollment_key(network_name),
           {:ok, _} <- Vpn.join_network([{:token, token} | join_opts]),
           :ok <- wait_for_netmaker(admin_name, 1, max_attempts),
           :ok <- wait_for_netclient(network_name, 1, max_attempts) do
        Logger.info("Successfully joined admin cluster network")
        :ok
      else
        {:error, reason} ->
          Logger.error("Failed to join admin cluster network: #{inspect(reason)}")
          # If we got far enough that a host might exist in Netmaker, delete
          # it so we don't leave a hostless orphan eating CIDR slots on retry.
          maybe_cleanup_orphan_self(admin_name, reason)
          {:error, {:vpn_join_failed, reason}}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    status =
      case result do
        :ok -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_admin, :membership, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :join_vpn, status: status}
    )

    result
  end

  # Pre-flight: refuse to attempt join if the admin cluster CIDR is exhausted.
  # Without this check, `wait_for_netclient` would hang because Netmaker accepts
  # the host registration but never creates a node (IP allocation fails inside
  # an async goroutine). Bail out early with a clear error instead.
  defp check_capacity(network_name) do
    case Vpn.network_has_capacity(network_name) do
      :ok ->
        :ok

      {:error, {:network_full, %{used: used, capacity: capacity}}} ->
        Logger.error(
          "Admin cluster network #{network_name} is full (#{used}/#{capacity} addresses used). " <>
            "Expand ADMIN_CLUSTER_SUBNET or evict stale admins before retrying."
        )

        {:error, {:admin_cluster_full, network_name, used, capacity}}

      {:error, :not_found} ->
        # Network was just created by ensure_network_exists/1, so this would be
        # a transient inconsistency. Treat as service_unavailable to retry.
        {:error, :service_unavailable}

      {:error, _} = error ->
        error
    end
  end

  defp ensure_network_exists(network_name) do
    # Get admin cluster subnet from env or generate from pool
    subnet =
      case admin_cluster_subnet() do
        nil -> Vpn.generate_next_subnet([])
        value -> value
      end

    Vpn.ensure_network_exists(network_name, %{addressrange: subnet})
  end

  defp build_join_opts(admin_name) do
    base_opts = [name: admin_name]

    # Add static port if ADMIN_WIREGUARD_PORT is configured
    # This ensures the admin listens on a predictable port for external agent connectivity
    case admin_wireguard_port() do
      nil ->
        Logger.info("No ADMIN_WIREGUARD_PORT configured, using dynamic port assignment")
        base_opts

      port when is_integer(port) ->
        Logger.info("Using static WireGuard port: #{port}")
        base_opts ++ [port: port, static_port: true]
    end
  end

  defp wait_for_netmaker(_admin_name, attempt, max_attempts) when attempt > max_attempts do
    {:error, :netmaker_registration_timeout}
  end

  defp wait_for_netmaker(admin_name, attempt, max_attempts) do
    case Vpn.get_host_id(admin_name) do
      {:ok, _host_id} ->
        Logger.info("Host #{admin_name} registered in Netmaker API")
        :ok

      _ ->
        Logger.debug("Waiting for #{admin_name} to appear in Netmaker (attempt #{attempt}/#{max_attempts})")

        Process.sleep(@join_retry_delay_ms)
        wait_for_netmaker(admin_name, attempt + 1, max_attempts)
    end
  end

  defp wait_for_netclient(_network_name, attempt, max_attempts) when attempt > max_attempts do
    {:error, :netclient_join_timeout}
  end

  defp wait_for_netclient(network_name, attempt, max_attempts) do
    case Vpn.netclient_health_check() do
      {:ok, status, info} when status in [:healthy, :degraded] ->
        if network_name in info[:networks] do
          Logger.info("Netclient connected to #{network_name}")
          :ok
        else
          Logger.debug(
            "Waiting for netclient to join #{network_name} (attempt #{attempt}/#{max_attempts}), " <>
              "current networks: #{inspect(info[:networks])}"
          )

          Process.sleep(@join_retry_delay_ms)
          wait_for_netclient(network_name, attempt + 1, max_attempts)
        end

      {:ok, :unhealthy, _info} ->
        Logger.debug("Waiting for netclient to become healthy (attempt #{attempt}/#{max_attempts})")

        Process.sleep(@join_retry_delay_ms)
        wait_for_netclient(network_name, attempt + 1, max_attempts)
    end
  end

  # Step 1 may have registered this admin as a host in Netmaker before failing
  # (e.g. node creation hung, netclient didn't pick up the network). Such a
  # host is an orphan: it occupies a slot but provides no functionality. Delete
  # it before propagating the error so the next restart starts from a clean
  # slate. Best-effort — failures here are logged but don't change the outcome.
  #
  # Skipped for `:admin_cluster_full` because we never attempted the join, so
  # nothing was created.
  defp maybe_cleanup_orphan_self(_admin_name, {:admin_cluster_full, _, _, _}), do: :ok

  defp maybe_cleanup_orphan_self(admin_name, _reason) do
    case Vpn.get_host_id(admin_name) do
      {:ok, host_id} ->
        Logger.warning("Cleaning up orphan host #{admin_name} (#{host_id}) before exiting")

        case Vpn.delete_host(host_id) do
          {:ok, _} ->
            Logger.info("Deleted orphan host #{host_id}")
            :ok

          {:error, reason} ->
            Logger.warning("Failed to delete orphan host #{host_id}: #{inspect(reason)}")
            :ok
        end

      _ ->
        # No host registered (or Netmaker unreachable) — nothing to clean up.
        :ok
    end
  end

  # =============================================================================
  # Step 2: Erlang Distribution
  # =============================================================================

  # Erlang distribution startup can fail transiently (epmd not yet up,
  # VPN hostname not yet resolvable). Retry a few times before giving up —
  # if it still won't come up, fail membership startup so the supervisor
  # crashes the app and the orchestrator restarts the container.
  @erlang_dist_max_attempts 5
  @erlang_dist_retry_delay_ms 2_000

  defp step_2_start_erlang_distribution do
    Logger.info("Step 2: Starting Erlang distribution")

    start_time = System.monotonic_time(:millisecond)

    vpn_hostname = Vpn.build_vpn_hostname(admin_name(), admin_cluster_name())
    node_name = Vpn.build_admin_erlang_node_name(vpn_hostname)

    Logger.info("Starting distributed node: #{node_name}")

    result = try_start_erlang_distribution(node_name, 1)

    duration = System.monotonic_time(:millisecond) - start_time

    status =
      case result do
        :ok -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_admin, :membership, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :start_erlang_distribution, status: status}
    )

    result
  end

  defp try_start_erlang_distribution(node_name, attempt) do
    case do_start_erlang_distribution(node_name) do
      :ok ->
        :ok

      {:error, reason} when attempt < @erlang_dist_max_attempts ->
        Logger.warning(
          "Erlang distribution startup failed (attempt #{attempt}/#{@erlang_dist_max_attempts}): " <>
            "#{inspect(reason)} — retrying in #{@erlang_dist_retry_delay_ms}ms"
        )

        Process.sleep(@erlang_dist_retry_delay_ms)
        try_start_erlang_distribution(node_name, attempt + 1)

      {:error, reason} ->
        Logger.error(
          "Erlang distribution startup failed after #{@erlang_dist_max_attempts} attempts: " <>
            "#{inspect(reason)}"
        )

        {:error, {:erlang_distribution_failed, reason}}
    end
  end

  defp do_start_erlang_distribution(node_name) do
    case Node.start(node_name, name_domain: :longnames) do
      {:ok, _pid} ->
        :erlang.set_cookie(node(), vpn_cluster_cookie())
        Logger.info("Erlang distribution started: #{node()}")
        :ok

      {:error, {:already_started, _pid}} ->
        :erlang.set_cookie(node(), vpn_cluster_cookie())
        Logger.info("Erlang distribution already started: #{node()}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  # =============================================================================
  # Step 3: Syn Registry
  # =============================================================================

  defp step_3_initialize_syn do
    Logger.info("Step 3: Initializing syn registry")

    start_time = System.monotonic_time(:millisecond)

    :syn.add_node_to_scopes([:admin_scope])

    {:ok, netmaker_host_id} = Vpn.get_host_id(admin_name())

    # Join the admin cluster group with metadata
    metadata = %{
      name: admin_name(),
      max_wireguard_peers: max_wireguard_peers(),
      vpn_hostname: Vpn.build_vpn_hostname(admin_name(), admin_cluster_name()),
      erlang_node_name: node(),
      netmaker_host_id: netmaker_host_id
    }

    :ok = :syn.join(:admin_scope, admin_cluster_name(), self(), metadata)
    Logger.info("Joined syn group :admin_scope/#{admin_cluster_name()} with metadata")

    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:edge_admin, :membership, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :initialize_syn, status: :success}
    )

    :ok
  end

  # =============================================================================
  # Step 4: Peer Discovery
  # =============================================================================

  defp step_4_discover_peers do
    Logger.info("Step 4: Discovering peer admins")

    start_time = System.monotonic_time(:millisecond)

    Discovery.scan_and_connect_admins()

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("Peer admin discovery completed")

    :telemetry.execute(
      [:edge_admin, :membership, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :discover_peers, status: :success}
    )

    :ok
  end
end
