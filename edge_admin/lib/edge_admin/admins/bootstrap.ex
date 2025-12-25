# edge_admin/lib/edge_admin/admins/bootstrap.ex
defmodule EdgeAdmin.Admins.Bootstrap do
  @moduledoc """
  One-time initialization GenServer for admin cluster bootstrap.

  Responsibilities:
  - VPN network join (admin cluster)
  - Erlang distribution startup
  - Peer admin discovery and connection
  - Syn registry initialization

  Bootstrap runs exactly once on application startup and blocks until complete.
  Any failure is fatal and crashes the supervision tree.

  ## Bootstrap Sequence

  1. Join VPN network (create if needed)
  2. Start Erlang distribution
  3. Discover and connect peer admins
  4. Initialize syn registry

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:admin_id` - Random 12-char identifier
  - `:admin_name` - "admin-{id}"
  - `:admin_cluster_name` - Peer admin cluster name
  - `:admin_max_capacity` - Max nodes this admin can handle
  - `:erlang_cookie` - Shared secret for Erlang distribution
  - `:admin_cluster_subnet` - Subnet for admin cluster (optional, auto-generates)
  """

  use GenServer

  require Logger

  alias EdgeAdmin.Admins.Discovery
  alias EdgeAdmin.Vpn

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
  defp erlang_cookie, do: Application.get_env(:edge_admin, :erlang_cookie)

  # =============================================================================
  # Bootstrap Flow
  # =============================================================================

  defp do_bootstrap do
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
  end

  # =============================================================================
  # Step 1: VPN Network Join
  # =============================================================================

  defp step_1_join_vpn do
    network_name = admin_cluster_name()
    admin_name = admin_name()
    Logger.info("Step 1: Joining VPN network #{network_name}")

    with :ok <- ensure_network_exists(network_name),
         {:ok, token} <- Vpn.get_default_enrollment_key(network_name),
         {:ok, _} <- Vpn.join_network(token: token, name: admin_name),
         :ok <- wait_for_host(admin_name),
         :ok <- verify_netclient_connection(network_name) do
      Logger.info("Successfully joined admin cluster network")
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to join admin cluster network: #{inspect(reason)}")
        {:error, {:vpn_join_failed, reason}}
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

  defp wait_for_host(admin_name) do
    case Vpn.get_host_id(admin_name) do
      {:ok, _host_id} ->
        Logger.info("Host #{admin_name} registered in Netmaker API")
        :ok

      _ ->
        Process.sleep(1000)
        wait_for_host(admin_name)
    end
  end

  defp verify_netclient_connection(network_name) do
    Logger.info("Verifying netclient connection to #{network_name}...")
    Process.sleep(5000)

    case Nexmaker.Cli.health_check() do
      {:ok, status, info} when status in [:healthy, :degraded] ->
        if network_name in info[:networks] do
          Logger.info("Netclient verified: connected to #{network_name}")
          :ok
        else
          {:error,
           "Netclient connected but not to #{network_name}, networks: #{inspect(info[:networks])}"}
        end

      {:ok, :unhealthy, info} ->
        {:error, "Netclient unhealthy after join: #{inspect(info[:warnings])}"}
    end
  end

  # =============================================================================
  # Step 2: Erlang Distribution
  # =============================================================================

  defp step_2_start_erlang_distribution do
    Logger.info("Step 2: Starting Erlang distribution")

    dns_hostname = Vpn.build_hostname(admin_name(), admin_cluster_name())
    node_name = Vpn.build_admin_erlang_node_name(dns_hostname)

    Logger.info("Starting distributed node: #{node_name}")

    try do
      case Node.start(node_name, :longnames) do
        {:ok, _pid} ->
          :erlang.set_cookie(node(), erlang_cookie())
          Logger.info("Erlang distribution started: #{node()}")
          :ok

        {:error, {:already_started, _pid}} ->
          :erlang.set_cookie(node(), erlang_cookie())
          Logger.info("Erlang distribution already started: #{node()}")
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to start Erlang distribution (will retry later): #{inspect(reason)}"
          )

          :ok
      end
    rescue
      e ->
        Logger.warning("Failed to start Erlang distribution (will retry later): #{inspect(e)}")
        :ok
    end
  end

  # =============================================================================
  # Step 3: Syn Registry
  # =============================================================================

  defp step_3_initialize_syn do
    Logger.info("Step 3: Initializing syn registry")
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

    case :syn.join(:admin_scope, admin_cluster_name(), self(), metadata) do
      :ok ->
        Logger.info("Joined syn group :admin_scope/#{admin_cluster_name()} with metadata")
        :ok

      {:error, reason} ->
        Logger.error("Failed to join syn group: #{inspect(reason)}")
        {:error, {:syn_join_failed, reason}}
    end
  end

  # =============================================================================
  # Step 4: Peer Discovery
  # =============================================================================

  defp step_4_discover_peers do
    Logger.info("Step 4: Discovering peer admins")
    Discovery.scan_and_connect_admins()
    Logger.info("Peer admin discovery completed")
    :ok
  end
end
