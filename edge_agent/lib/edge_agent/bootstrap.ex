# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  Bootstrap module for agent initialization and orchestration.

  Handles the complete agent startup sequence:
  1. Determine node identity (machine_id, hardware_id, or temporary_id)
  2. Connect to VPN (future step)
  3. Register with admin (future step)
  4. Store configuration (future step)
  """

  require Logger

  alias EdgeAgent.Settings

  @doc """
  Runs the complete bootstrap sequence.

  Returns {:ok, :bootstrap_complete} on success or {:error, reason} on failure.
  """
  def run do
    Logger.info("Starting EdgeAgent bootstrap sequence...")

    with {:ok, node_id, node_id_type} <- determine_node_identity(),
         {:ok, _} <- store_node_identity(node_id, node_id_type) do
      Logger.info("Bootstrap sequence completed successfully")
      {:ok, :bootstrap_complete}
    else
      {:error, reason} = error ->
        Logger.error("Bootstrap sequence failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Determines the node identity using the 3-tier approach:
  1. machine_id (from systemd/dbus)
  2. hardware_id (from DMI/hardware sources)
  3. temporary_id (generated UUID)

  Returns {:ok, node_id, node_id_type} or {:error, reason}.
  """
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
            Logger.warning("Generated temporary_id: #{String.slice(node_id, 0, 8)}... (node will be ephemeral)")
            {:ok, node_id, "temporary_id"}
        end
    end
  end

  # PRIVATE FUNCTIONS

  defp store_node_identity(node_id, node_id_type) do
    Logger.info("Storing node identity: type=#{node_id_type}")

    case Settings.set_node_identity(node_id, node_id_type) do
      {:ok, _} ->
        {:ok, :stored}
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
      String.match?(content, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i) -> true
      # UUID format (without dashes)
      String.match?(content, ~r/^[a-f0-9]{32}$/i) -> true
      # Serial number (alphanumeric, 6-64 chars)
      String.match?(content, ~r/^[a-zA-Z0-9]{6,64}$/) -> true
      # Default
      true -> false
    end
  end
end
