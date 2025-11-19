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

  1. Check if bootstrap should run (skip in test, require PHX_SERVER=true)
  2. Ensure VPN joined
  3. Start Erlang distribution
  4. Query network info (subnet) at runtime
  5. Scan subnet for peer admins and connect
  6. Initialize syn (add scopes + register self)
  7. Mark as initialized

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:admin_id` - Random 12-char identifier
  - `:admin_name` - "admin-{id}"
  - `:admin_cluster_name` - Peer admin cluster name
  - `:admin_max_capacity` - Max nodes this admin can handle
  - `:erlang_cookie` - Shared secret for Erlang distribution
  - `:netmaker_default_domain` - DNS domain suffix
  """

  use GenServer

  require Logger

  alias EdgeAdmin.Admins.Discovery

  # === Public API ===

  @doc """
  Starts the Bootstrap GenServer.

  Options:
  - `:skip_bootstrap` - Skip bootstrap entirely (for testing)
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

  # === GenServer Callbacks ===

  @impl true
  def init(opts) do
    if should_run?(opts) do
      Logger.info("Bootstrap starting...")

      case do_bootstrap() do
        :ok ->
          Logger.info("Bootstrap completed successfully")
          {:ok, %{status: :complete, initialized: true}}

        {:error, reason} ->
          Logger.error("Bootstrap failed: #{inspect(reason)}")
          {:stop, reason}
      end
    else
      Logger.info("Bootstrap skipped")
      {:ok, %{status: :skipped, initialized: false}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  # === Private Helpers ===

  defp should_run?(opts) do
    cond do
      Keyword.get(opts, :skip_bootstrap, false) ->
        false

      Application.get_env(:edge_admin, :run_bootstrap) == false ->
        false

      Mix.env() == :test ->
        false

      true ->
        System.get_env("PHX_SERVER") == "true"
    end
  end

  defp do_bootstrap do
    # Read config values
    admin_id = Application.get_env(:edge_admin, :admin_id)
    admin_name = Application.get_env(:edge_admin, :admin_name)
    admin_cluster_name = Application.get_env(:edge_admin, :admin_cluster_name)
    max_capacity = Application.get_env(:edge_admin, :admin_max_capacity)
    erlang_cookie = Application.get_env(:edge_admin, :erlang_cookie)

    with :ok <- ensure_vpn_joined(admin_cluster_name),
         :ok <- start_erlang_distribution(admin_name, admin_cluster_name, erlang_cookie),
         :ok <- discover_and_connect_peers(admin_cluster_name),
         :ok <- initialize_syn(admin_id, admin_cluster_name, max_capacity) do
      Logger.info("All bootstrap steps completed")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Bootstrap step failed: #{inspect(reason)}")
        error
    end
  end

  defp ensure_vpn_joined(admin_cluster_name) do
    Logger.info("Joining VPN network #{admin_cluster_name}")

    # Always create network if needed, create enrollment key, and join
    # This is idempotent - netclient handles re-registration and updates hostname
    case Discovery.create_and_join_admin_cluster(admin_cluster_name) do
      :ok ->
        Logger.info("Successfully joined admin cluster network")
        :ok

      {:error, reason} ->
        Logger.error("Failed to join admin cluster network: #{inspect(reason)}")
        {:error, {:vpn_join_failed, reason}}
    end
  end

  defp start_erlang_distribution(admin_name, admin_cluster_name, erlang_cookie) do
    Logger.info("Starting Erlang distribution")

    # Build node name from config
    netmaker_default_domain = Application.get_env(:edge_admin, :netmaker_default_domain)

    node_name =
      if netmaker_default_domain == "" do
        :"admin@#{admin_name}.#{admin_cluster_name}"
      else
        :"admin@#{admin_name}.#{admin_cluster_name}.#{netmaker_default_domain}"
      end

    Logger.info("Starting distributed node: #{node_name}")

    try do
      case Node.start(node_name, :longnames) do
        {:ok, _pid} ->
          # Set cookie after node starts
          :erlang.set_cookie(node(), erlang_cookie)
          Logger.info("Erlang distribution started: #{node()}")
          :ok

        {:error, {:already_started, _pid}} ->
          # Set cookie if node already started
          :erlang.set_cookie(node(), erlang_cookie)
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
  end

  defp discover_and_connect_peers(_admin_cluster_name) do
    # Discovery now fetches network info dynamically
    Logger.info("Starting peer admin discovery")
    Discovery.scan_and_connect_admins()
    Logger.info("Peer admin discovery completed")
    :ok
  end

  defp initialize_syn(admin_id, admin_cluster_name, max_capacity) do
    Logger.info("Initializing syn registry")

    # Add node to syn scopes
    :syn.add_node_to_scopes([:admin_scope])
    Logger.debug("Added node to :admin_scope")

    # Join the admin cluster group with metadata
    # This allows all admins in the same cluster to find each other
    metadata = %{
      id: admin_id,
      max_capacity: max_capacity,
      erlang_node_name: node()
    }

    # Join the admin cluster group (not register with a key)
    # :syn.join/4 is used for group membership (process groups)
    case :syn.join(:admin_scope, admin_cluster_name, self(), metadata) do
      :ok ->
        Logger.info("Joined syn group :admin_scope/#{admin_cluster_name} with metadata")
        :ok

      {:error, reason} ->
        Logger.error("Failed to join syn group: #{inspect(reason)}")
        {:error, {:syn_join_failed, reason}}
    end
  end
end
