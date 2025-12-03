# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  Bootstrap orchestrator for edge agent startup.

  Coordinates node identity determination, VPN join, admin discovery,
  registration, and command sync. Exits program on any failure.

  ## Bootstrap Sequence

  1. Determine node identity
  2. Join VPN network
  3. Discover admins
  4. Register with admin
  5. Get sent command executions

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:enrollment_key` - Netmaker enrollment token
  - `:run_bootstrap` - Whether to run bootstrap (default: true)
  """

  use GenServer

  require Logger

  alias EdgeAgent.Identity
  alias EdgeAgent.EdgeClusters.Discovery
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings
  alias EdgeAgent.Commands

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
    if Application.get_env(:edge_agent, :run_bootstrap, true) do
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
      Logger.info("Bootstrap skipped (disabled in config or test environment)")
      {:ok, %{status: :skipped, initialized: false}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  # =============================================================================
  # Bootstrap Flow
  # =============================================================================

  defp do_bootstrap do
    with {:ok, node_id, id_type} <- step_1_determine_identity(),
         :ok <- step_2_join_vpn(node_id),
         {:ok, network_name, _admin_urls} <- step_3_discover_admins(),
         :ok <- step_4_register_node(node_id, id_type, network_name),
         :ok <- step_5_get_sent_command_executions(node_id) do
      Logger.info("All bootstrap steps completed")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Bootstrap step failed: #{inspect(reason)}")
        error
    end
  end

  # =============================================================================
  # Step 1: Determine Identity
  # =============================================================================

  defp step_1_determine_identity do
    Logger.info("Step 1: Determining node identity...")

    case Identity.determine() do
      {:ok, node_id, id_type} ->
        Logger.info("Node identity: #{String.slice(node_id, 0, 8)}... (#{id_type})")

        # Store identity in settings for persistence across restarts
        Settings.set_node_id(node_id)
        Settings.set_id_type(id_type)

        {:ok, node_id, id_type}

      {:error, reason} ->
        {:error, "Failed to determine node identity: #{inspect(reason)}"}
    end
  end

  # =============================================================================
  # Step 2: Join VPN
  # =============================================================================

  defp step_2_join_vpn(node_id) do
    Logger.info("Step 2: Joining VPN network...")

    with {:ok, :not_connected} <- Nexmaker.Cli.check_any_connection(),
         {:ok, _} <- join_and_verify(node_id) do
      :ok
    else
      {:ok, :connected} ->
        Logger.info("Already connected to network, skipping join...")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp join_and_verify(node_id) do
    Logger.info("No networks found, joining VPN...")

    enrollment_key = Application.get_env(:edge_agent, :enrollment_key)
    node_name = "node-#{node_id}"

    with {:ok, _} <- Nexmaker.Cli.join_network(token: enrollment_key, name: node_name),
         :ok <- wait_and_verify_connection() do
      {:ok, :joined}
    else
      {:error, reason} ->
        {:error, "VPN join failed: #{inspect(reason)}"}
    end
  end

  defp wait_and_verify_connection do
    Logger.info("Join command completed, verifying connection...")
    Process.sleep(5000)

    case Nexmaker.Cli.check_any_connection() do
      {:ok, :connected} ->
        Logger.info("VPN connection verified successfully")
        :ok

      {:ok, :not_connected} ->
        {:error, "Join command succeeded but no networks found - enrollment key may be invalid"}

      {:error, reason} ->
        {:error, "Failed to verify join: #{inspect(reason)}"}
    end
  end

  # =============================================================================
  # Step 3: Discover Admins
  # =============================================================================

  defp step_3_discover_admins do
    Logger.info("Step 3: Discovering admins...")

    # Bootstrap requires at least one admin to be discovered (fail fast)
    case Discovery.discover_admins(fail_on_empty: true) do
      {:ok, network_name, admin_urls} ->
        Logger.info("Network: #{network_name}")
        Logger.info("Discovered #{length(admin_urls)} admin(s)")
        {:ok, network_name, admin_urls}

      {:error, reason} ->
        {:error, "Admin discovery failed: #{inspect(reason)}"}
    end
  end

  # =============================================================================
  # Step 4: Register Node
  # =============================================================================

  defp step_4_register_node(node_id, id_type, network_name) do
    Logger.info("Step 4: Registering with admin...")

    payload = build_registration_payload(node_id, id_type, network_name)

    case AdminClient.register_node(payload) do
      {:ok, node_data} ->
        # Store API token and proxy password from registration response
        api_token = node_data["api_token"]
        proxy_password = node_data["proxy_password"]

        cond do
          is_nil(api_token) ->
            {:error, "Registration response missing api_token"}

          is_nil(proxy_password) ->
            {:error, "Registration response missing proxy_password"}

          true ->
            Settings.set_api_token(api_token)
            Settings.set_proxy_password(proxy_password)
            Logger.info("Successfully registered with admin")
            :ok
        end

      {:error, reason} ->
        {:error, "Registration failed: #{inspect(reason)}"}
    end
  end

  # =============================================================================
  # Step 5: Get Sent Command Executions
  # =============================================================================

  defp step_5_get_sent_command_executions(_node_id) do
    Logger.info("Step 5: Syncing pending commands...")

    case AdminClient.get_sent_command_executions() do
      {:ok, commands} ->
        Logger.info("Synced #{length(commands)} pending command(s)")

        # Store each command in local database and trigger execution
        Enum.each(commands, fn command ->
          attrs = %{
            id: command["id"],
            command_id: command["command_id"],
            node_id: Settings.get_node_id(),
            command_text: command["command_text"],
            status: "pending"
          }

          case Commands.create_command_execution_and_maybe_start_worker(attrs) do
            {:ok, _execution} ->
              Logger.debug("Stored command execution: #{command["id"]}")
            {:error, changeset} ->
              Logger.warning("Failed to store command execution #{command["id"]}: #{inspect(changeset.errors)}")
          end
        end)

        :ok

      {:error, reason} ->
        Logger.warning("Command sync failed (non-fatal): #{inspect(reason)}")
        :ok
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp build_registration_payload(node_id, id_type, network_name) do
    %{
      node_id: node_id,
      id_type: id_type,
      network_name: network_name,
      http_port: Application.get_env(:edge_agent, :http_port, 44000),
      ssh_port: Application.get_env(:edge_agent, :ssh_port, 40022),
      metrics_port: Application.get_env(:edge_agent, :metrics_port, 49100),
      http_proxy_port: Application.get_env(:edge_agent, :http_proxy_port, 43128),
      socks5_proxy_port: Application.get_env(:edge_agent, :socks5_proxy_port, 41080)
    }
  end
end
