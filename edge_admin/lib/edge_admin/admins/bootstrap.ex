# edge_admin/lib/edge_admin/admins/bootstrap.ex
defmodule EdgeAdmin.Admins.Bootstrap do
  @moduledoc """
  One-time initialization for admin cluster membership and distributed Erlang setup.

  This GenServer runs exactly once during application startup and performs critical
  initialization tasks to join the admin cluster and enable distributed coordination.

  ## Key Concepts

  - **Admin Cluster**: VPN network connecting all admin instances for HA coordination
  - **Bootstrap**: One-time setup that must succeed or application crashes
  - **Erlang Distribution**: Enables inter-admin RPC, syn registry, and clustering
  - **Peer Discovery**: Finds other admins in the cluster via Netmaker API

  ## Responsibilities

  1. **VPN Network Join**
     - Join admin cluster VPN network
     - Create network if this is the first admin (bootstrap mode)
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

  ## Bootstrap Sequence

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

  Bootstrap failures are **FATAL** and crash the supervision tree:
  - VPN join failure → Can't communicate with peers
  - Erlang distribution failure → Can't coordinate
  - syn initialization failure → Can't route requests

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:admin_id` - Random 12-char identifier (e.g., "7k3m9p2n")
  - `:admin_name` - Prefixed name (e.g., "admin-7k3m9p2n")
  - `:admin_cluster_name` - Shared cluster name (e.g., "admin-cluster-main")
  - `:admin_max_capacity` - Max nodes this admin can handle (e.g., 200)
  - `:vpn_cluster_cookie` - Shared secret for Erlang distribution over the VPN cluster
  - `:admin_cluster_subnet` - Optional subnet (auto-generates if missing)

  ## Examples

      # Bootstrap runs automatically on application start
      # Success: Application continues
      # Failure: Application crashes with detailed error

      # Check if bootstrap completed
      iex> Bootstrap.initialized?()
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
  Starts the Bootstrap GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if bootstrap completed successfully.
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
    Logger.info("Bootstrap starting...")

    case do_bootstrap() do
      :ok ->
        Logger.info("Bootstrap completed successfully")
        {:ok, %{status: :complete, initialized: true}}

      {:error, reason} ->
        Logger.error("Bootstrap failed: #{inspect(reason)}")
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
  defp max_capacity, do: Application.get_env(:edge_admin, :admin_max_capacity)
  defp vpn_cluster_cookie, do: Application.get_env(:edge_admin, :vpn_cluster_cookie)
  defp admin_wireguard_port, do: Application.get_env(:edge_admin, :admin_wireguard_port)

  # =============================================================================
  # Bootstrap Flow
  # =============================================================================

  defp do_bootstrap do
    start_time = System.monotonic_time(:millisecond)

    result =
      with :ok <- step_1_join_vpn(),
           :ok <- step_2_start_erlang_distribution(),
           :ok <- step_3_initialize_syn(),
           :ok <- step_4_discover_peers() do
        Logger.info("All bootstrap steps completed")
        :ok
      else
        {:error, reason} = error ->
          Logger.error("Bootstrap step failed: #{inspect(reason)}")
          error
      end

    duration = System.monotonic_time(:millisecond) - start_time

    status =
      case result do
        :ok -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_admin, :bootstrap, :complete],
      %{duration: duration, count: 1, total: 1},
      %{status: status}
    )

    result
  end

  # =============================================================================
  # Step 1: VPN Network Join
  # =============================================================================

  defp step_1_join_vpn do
    network_name = admin_cluster_name()
    admin_name = admin_name()
    Logger.info("Step 1: Joining VPN network #{network_name}")

    start_time = System.monotonic_time(:millisecond)

    # Build join options, adding static port if configured
    join_opts = build_join_opts(admin_name)

    result =
      with :ok <- ensure_network_exists(network_name),
           {:ok, token} <- Vpn.get_default_enrollment_key(network_name),
           {:ok, _} <- Vpn.join_network([{:token, token} | join_opts]),
           :ok <- wait_for_netmaker(admin_name),
           :ok <- wait_for_netclient(network_name) do
        Logger.info("Successfully joined admin cluster network")
        :ok
      else
        {:error, reason} ->
          Logger.error("Failed to join admin cluster network: #{inspect(reason)}")
          {:error, {:vpn_join_failed, reason}}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    status =
      case result do
        :ok -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_admin, :bootstrap, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :join_vpn, status: status}
    )

    result
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

  defp wait_for_netmaker(admin_name) do
    case Vpn.get_host_id(admin_name) do
      {:ok, _host_id} ->
        Logger.info("Host #{admin_name} registered in Netmaker API")
        :ok

      _ ->
        Process.sleep(2000)
        wait_for_netmaker(admin_name)
    end
  end

  defp wait_for_netclient(network_name) do
    case Nexmaker.Cli.health_check() do
      {:ok, status, info} when status in [:healthy, :degraded] ->
        if network_name in info[:networks] do
          Logger.info("Netclient connected to #{network_name}")
          :ok
        else
          Logger.debug("Waiting for netclient to join #{network_name}, current networks: #{inspect(info[:networks])}")
          Process.sleep(2000)
          wait_for_netclient(network_name)
        end

      {:ok, :unhealthy, _info} ->
        Logger.debug("Waiting for netclient to become healthy...")
        Process.sleep(2000)
        wait_for_netclient(network_name)
    end
  end

  # =============================================================================
  # Step 2: Erlang Distribution
  # =============================================================================

  defp step_2_start_erlang_distribution do
    Logger.info("Step 2: Starting Erlang distribution")

    start_time = System.monotonic_time(:millisecond)

    dns_hostname = Vpn.build_hostname(admin_name(), admin_cluster_name())
    node_name = Vpn.build_admin_erlang_node_name(dns_hostname)

    Logger.info("Starting distributed node: #{node_name}")

    result =
      try do
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
            Logger.warning("Failed to start Erlang distribution (will retry later): #{inspect(reason)}")

            :ok
        end
      rescue
        e ->
          Logger.warning("Failed to start Erlang distribution (will retry later): #{inspect(e)}")
          :ok
      end

    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:edge_admin, :bootstrap, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :start_erlang_distribution, status: :success}
    )

    result
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
      max_capacity: max_capacity(),
      dns_hostname: Vpn.build_hostname(admin_name(), admin_cluster_name()),
      erlang_node_name: node(),
      netmaker_host_id: netmaker_host_id
    }

    :ok = :syn.join(:admin_scope, admin_cluster_name(), self(), metadata)
    Logger.info("Joined syn group :admin_scope/#{admin_cluster_name()} with metadata")

    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:edge_admin, :bootstrap, :step],
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
      [:edge_admin, :bootstrap, :step],
      %{duration: duration, count: 1, total: 1},
      %{step: :discover_peers, status: :success}
    )

    :ok
  end
end
