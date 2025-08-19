# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  Bootstrap module for agent initialization and orchestration.

  Handles the complete agent startup sequence:
  1. Determine node identity (machine_id, hardware_id, or temporary_id)
  2. Store node identity in settings
  3. Connect to VPN using node-specific hostname (node-{uuid})
  4. Connect to EdgeAdmin via get-or-create pattern
  5. Store node settings from EdgeAdmin
  6. Start SSH server for remote access

  Returns {:ok, :bootstrap_complete} on success or {:error, reason} on failure.
  """

  require Logger

  alias EdgeAgent.Settings
  alias EdgeAgent.VPN
  alias EdgeAgent.AdminClient
  alias EdgeAgent.SshServer
  alias EdgeAgent.MetricsServer

  def run(opts \\ []) do
    Logger.info("Starting EdgeAgent bootstrap...")

    vpn_module = Keyword.get(opts, :vpn_module, VPN)
    admin_client_module = Keyword.get(opts, :admin_client_module, AdminClient)
    ssh_server_module = Keyword.get(opts, :ssh_server_module, SshServer)
    metrics_server_module = Keyword.get(opts, :metrics_server_module, MetricsServer)

    with {:ok, node_id, node_id_type} <- determine_node_identity(),
         {:ok, normalized_node_id} <- store_node_identity(node_id, node_id_type),
         :ok <- setup_vpn_connection(normalized_node_id, vpn_module),
         settings <- Settings.all(),
         {:ok, _} <- connect_to_admin(settings, admin_client_module),
         :ok <- start_ssh_server(ssh_server_module),
         :ok <- start_metrics_server(metrics_server_module) do
      Logger.info("Bootstrap sequence completed successfully")
      {:ok, :bootstrap_complete}
    else
      {:error, reason} = error ->
        Logger.error("Bootstrap sequence failed: #{inspect(reason)}")
        error
    end
  end

  def determine_node_identity do
    Logger.info("Determining node identity...")

    case try_machine_id() do
      {:ok, node_id} ->
        Logger.info("Found machine_id: #{String.slice(node_id, 0, 8)}...")
        {:ok, node_id, "machine_id"}

      :error ->
        case try_hardware_id() do
          {:ok, node_id} ->
            Logger.info("Found hardware_id: #{String.slice(node_id, 0, 8)}...")
            {:ok, node_id, "hardware_id"}

          :error ->
            node_id = generate_temporary_id()

            Logger.warning(
              "Generated temporary_id: #{String.slice(node_id, 0, 8)}... (node will be ephemeral)"
            )

            {:ok, node_id, "temporary_id"}
        end
    end
  end

  def setup_vpn_connection(node_id, vpn_module \\ VPN) do
    Logger.info("Setting up VPN connection for node: #{String.slice(node_id, 0, 8)}...")

    vpn_url = Application.get_env(:edge_agent, :vpn_url)
    enrollment_key = Application.get_env(:edge_agent, :enrollment_key)
    hostname = "node-#{node_id}"

    with :ok <- vpn_module.start_daemon(),
         {:ok, _result} <- vpn_module.connect_to_vpn(vpn_url, enrollment_key, hostname),
         {:ok, vpn_ip} <- validate_vpn_connection(vpn_module),
         {:ok, _connection} <- vpn_module.sync_connection_state() do
      Logger.info("Successfully connected to VPN with IP: #{vpn_ip}")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("VPN connection failed: #{inspect(reason)}")
        error
    end
  end

  def connect_to_admin(settings, admin_client_module \\ AdminClient) do
    node_id = Map.get(settings, "id")
    node_id_type = Map.get(settings, "id_type")

    Logger.info("Connecting to admin for node: #{String.slice(node_id || "unknown", 0, 8)}...")

    case admin_client_module.get_node(node_id) do
      {:ok, node_data} ->
        Logger.info("Node already registered with admin")
        store_node_settings_from_admin(node_data)

      {:error, :not_found} ->
        Logger.info("Node not found, registering with admin...")
        register_new_node(node_id, node_id_type, admin_client_module)

      {:error, reason} ->
        Logger.error("Failed to connect to admin: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def start_ssh_server(ssh_server_module \\ SshServer) do
    Logger.info("Starting SSH server...")

    case ssh_server_module.start_server() do
      :ok ->
        Logger.info("SSH server started successfully")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start SSH server: #{inspect(reason)}")
        # For now, we'll treat SSH server failure as non-fatal
        # You might want to change this behavior later
        Logger.warning("Continuing bootstrap despite SSH server failure")
        :ok
    end
  end

  def start_metrics_server(metrics_server_module \\ MetricsServer) do
    Logger.info("Starting metrics server...")

    case metrics_server_module.start_server() do
      {:ok, _pid} ->
        Logger.info("Metrics server started successfully")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start metrics server: #{inspect(reason)}")
        # For now, we'll treat metrics server failure as non-fatal
        # You might want to change this behavior later
        Logger.warning("Continuing bootstrap despite metrics server failure")
        :ok
    end
  end

  # PRIVATE FUNCTIONS

  # Node Identity Helpers

  defp store_node_identity(node_id, node_id_type) do
    Logger.info("Storing node identity: type=#{node_id_type}")

    case Settings.set_node_identity(node_id, node_id_type) do
      {:ok, %{id: normalized_node_id}} ->
        Logger.info("Stored normalized node ID: #{String.slice(normalized_node_id, 0, 8)}...")
        {:ok, normalized_node_id}

      {:error, reason} ->
        {:error, "Failed to store node identity: #{reason}"}
    end
  end

  # Tier 1: Machine ID Detection

  defp try_machine_id do
    machine_id_paths = [
      "/host/etc/machine-id",
      "/host/var/lib/dbus/machine-id"
    ]

    machine_id_paths
    |> Enum.find_value(:error, fn path ->
      case read_file_safely(path) do
        {:ok, content} ->
          cleaned = String.trim(content)
          if valid_machine_id?(cleaned), do: {:ok, cleaned}, else: false

        :error ->
          false
      end
    end)
  end

  # Tier 2: Hardware ID Detection

  defp try_hardware_id do
    hardware_id_paths = [
      "/host/sys/class/dmi/id/product_uuid",
      "/host/sys/class/dmi/id/board_serial",
      "/host/sys/class/dmi/id/product_serial",
      "/host/proc/sys/kernel/random/boot_id"
    ]

    hardware_id_paths
    |> Enum.find_value(:error, fn path ->
      case read_file_safely(path) do
        {:ok, content} ->
          cleaned = String.trim(content)
          if valid_hardware_id?(cleaned), do: {:ok, cleaned}, else: false

        :error ->
          false
      end
    end)
  end

  # Tier 3: Temporary ID Generation

  defp generate_temporary_id do
    Ecto.UUID.generate()
  end

  # File Reading Helpers

  defp read_file_safely(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> :error
    end
  end

  # Validation Helpers

  defp valid_machine_id?(content) do
    # Machine IDs should be 32 hex characters
    String.match?(content, ~r/^[a-f0-9]{32}$/i) && String.length(content) == 32
  end

  defp valid_hardware_id?(content) do
    # Hardware IDs can be UUIDs or serial numbers
    # Accept UUIDs (with or without dashes) or alphanumeric serials
    cond do
      # UUID format (with dashes)
      String.match?(content, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i) ->
        true

      # UUID format (without dashes)
      String.match?(content, ~r/^[a-f0-9]{32}$/i) ->
        true

      # Serial number (alphanumeric, 6-64 chars)
      String.match?(content, ~r/^[a-zA-Z0-9]{6,64}$/) ->
        true

      # Default
      true ->
        false
    end
  end

  # VPN Connection Helpers

  defp validate_vpn_connection(vpn_module) do
    Logger.info("Validating VPN connection...")

    case vpn_module.get_vpn_ip() do
      {:ok, vpn_ip} ->
        Logger.info("VPN connection validated with IP: #{vpn_ip}")
        {:ok, vpn_ip}

      {:error, _} ->
        {:error, "VPN connection validation failed - no IP assigned"}
    end
  end

  # Admin Connection Helpers

  defp register_new_node(node_id, node_id_type, admin_client_module) do
    node_params = %{
      id: node_id,
      id_type: node_id_type,
      status: "online"
    }

    case admin_client_module.create_node(node_params) do
      {:ok, node_data} ->
        Logger.info("Successfully registered new node with admin")
        store_node_settings_from_admin(node_data)

      {:error, reason} ->
        Logger.error("Failed to register node with admin: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store_node_settings_from_admin(node_data) do
    Logger.info("Storing admin response data...")

    # Define the mapping from node_data keys to config keys
    key_mapping = %{
      "id" => "id",
      "id_type" => "id_type",
      "vpn_ip" => "vpn_ip",
      "vpn_hostname" => "vpn_hostname",
      "status" => "status",
      "last_seen_at" => "last_seen_at"
    }

    # Filter out nil values and store only what we have
    storage_results =
      node_data
      |> Enum.filter(fn {_key, value} -> not is_nil(value) end)
      |> Enum.filter(fn {key, _value} -> Map.has_key?(key_mapping, key) end)
      |> Enum.map(fn {node_key, value} ->
        config_key = Map.get(key_mapping, node_key)

        case Settings.set(config_key, value) do
          {:ok, _} ->
            Logger.debug("Stored #{config_key}: #{inspect(value)}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to store #{config_key}: #{inspect(reason)}")
            {:error, {config_key, reason}}
        end
      end)

    # Check if any storage operations failed
    case Enum.find(storage_results, fn result -> match?({:error, _}, result) end) do
      nil ->
        stored_count = length(storage_results)
        Logger.info("Successfully stored #{stored_count} admin configuration values")
        {:ok, node_data}

      {:error, {key, reason}} ->
        Logger.error("Failed to store #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
