# edge_admin/lib/edge_admin/tailscale.ex
defmodule EdgeAdmin.Tailscale do
  @moduledoc """
  Pure Tailscale client - handles VPN operations without state management.

  This module provides a clean API for VPN operations and delegates all
  state management to the VPN context.
  """

  @behaviour EdgeAdmin.Tailscale.Behaviour

  require Logger

  @type connection_result :: {:ok, map()} | {:ok, :no_info} | {:error, String.t()}
  @type connectivity_result :: {:ok, map()} | {:ok, :healthy} | {:error, String.t()}

  # High-level operations for VPN context

  @doc """
  Connects to VPN and returns connection info.
  Handles the complete connection flow including daemon startup.
  """
  @spec connect_to_vpn(String.t(), String.t()) :: connection_result()
  def connect_to_vpn(vpn_url, hostname \\ "edge-admin") do
    Logger.info("Tailscale: Initiating connection to #{vpn_url} with hostname #{hostname}")

    with :ok <- ensure_daemon_running(),
         :ok <- perform_connection(vpn_url, hostname),
         result <- get_connection_info() do
      Logger.info("Tailscale: Connection flow completed successfully")
      result
    else
      {:error, reason} = error ->
        Logger.error("Tailscale: Connection flow failed - #{reason}")
        error
    end
  end

  @doc """
  Checks connectivity and returns current VPN information.
  """
  @spec check_connectivity() :: connectivity_result()
  def check_connectivity do
    case status_json() do
      {:ok, status_data} when is_map(status_data) ->
        if connected?(status_data) do
          case extract_vpn_info(status_data) do
            info when map_size(info) > 0 -> {:ok, info}
            _empty -> {:ok, :healthy}
          end
        else
          {:error, "Not connected"}
        end

      {:error, reason} ->
        {:error, "Status check failed: #{reason}"}
    end
  end

  @doc """
  Disconnects from VPN.
  """
  @spec disconnect_from_vpn() :: :ok | {:error, String.t()}
  def disconnect_from_vpn do
    Logger.info("Tailscale: Initiating disconnection")

    case System.cmd("tailscale", ["down"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Tailscale: Disconnected successfully")
        :ok

      {output, _code} ->
        error_msg = "Disconnect failed: #{String.trim(output)}"
        Logger.error("Tailscale: #{error_msg}")
        {:error, error_msg}
    end
  rescue
    e ->
      error_msg = "Disconnect failed: #{inspect(e)}"
      Logger.error("Tailscale: #{error_msg}")
      {:error, error_msg}
  end

  # Utility functions

  @doc """
  Gets Tailscale status as JSON.
  """
  def status_json do
    case System.cmd("tailscale", ["status", "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, "JSON decode failed"}
        end

      {output, _code} ->
        {:error, "CLI error: #{String.trim(output)}"}
    end
  end

  @doc """
  Checks if Tailscale is connected based on status data.
  """
  def connected?(status_data) when is_map(status_data) do
    backend_state = get_in(status_data, ["BackendState"])
    self_online = get_in(status_data, ["Self", "Online"])

    backend_state in ["Running", "Starting"] and self_online == true and
      not logged_out?(status_data)
  end

  def connected?(_), do: false

  # Private functions

  defp ensure_daemon_running do
    case System.cmd("tailscale", ["status"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.debug("Tailscale: Daemon already running")
        :ok

      {_output, _} ->
        Logger.info("Tailscale: Starting daemon")
        start_daemon()
    end
  end

  defp start_daemon do
    ensure_directories()

    cmd =
      "tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock"

    spawn(fn ->
      System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)
    end)

    :timer.sleep(2000)
    Logger.info("Tailscale: Daemon started")
    :ok
  end

  defp perform_connection(vpn_url, hostname) do
    if already_connected?(hostname) do
      Logger.info("Tailscale: Already connected with hostname #{hostname}")
      :ok
    else
      attempt_connection(vpn_url, hostname)
    end
  end

  defp already_connected?(hostname) do
    case System.cmd("tailscale", ["status"], stderr_to_stdout: true) do
      {output, 0} ->
        has_hostname = String.contains?(output, hostname)
        has_vpn_ip = Regex.match?(~r/100\.\d+\.\d+\.\d+/, output)
        has_hostname && has_vpn_ip

      {_output, _} ->
        false
    end
  end

  defp attempt_connection(vpn_url, hostname) do
    state_file = "/var/lib/tailscale/tailscaled.state"

    if File.exists?(state_file) and File.stat!(state_file).size > 0 do
      Logger.info("Tailscale: Found existing state, attempting reconnection")
      attempt_reconnect(vpn_url, hostname)
    else
      Logger.info("Tailscale: No existing state, performing fresh connection")
      fresh_connect(vpn_url, hostname)
    end
  end

  defp attempt_reconnect(vpn_url, hostname) do
    args = ["up", "--login-server=#{vpn_url}", "--accept-dns=false", "--hostname=#{hostname}"]

    case System.cmd("tailscale", args, stderr_to_stdout: true) do
      {_output, 0} ->
        :timer.sleep(2000)

        if verify_connection() do
          Logger.info("Tailscale: Reconnected successfully using existing credentials")
          :ok
        else
          Logger.info("Tailscale: Reconnection failed, trying fresh connection")
          fresh_connect(vpn_url, hostname)
        end

      {output, _} ->
        Logger.warning("Tailscale: Reconnection failed: #{String.trim(output)}")
        fresh_connect(vpn_url, hostname)
    end
  end

  defp fresh_connect(vpn_url, hostname) do
    Logger.info("Tailscale: Performing fresh connection")

    args = ["up", "--login-server=#{vpn_url}", "--accept-dns=false", "--hostname=#{hostname}"]

    case System.cmd("tailscale", args, stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Tailscale: Fresh connection successful")
        :ok

      {output, exit_code} ->
        error_msg = "Connection failed: #{String.trim(output)} (exit: #{exit_code})"
        Logger.error("Tailscale: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp get_connection_info do
    case check_connectivity() do
      {:ok, info} when is_map(info) -> {:ok, info}
      {:ok, :healthy} -> {:ok, :no_info}
      # Connected but can't get detailed info
      {:error, _reason} -> {:ok, :no_info}
    end
  end

  defp verify_connection do
    case System.cmd("tailscale", ["status"], stderr_to_stdout: true) do
      {output, 0} -> Regex.match?(~r/100\.\d+\.\d+\.\d+/, output)
      {_output, _} -> false
    end
  end

  defp logged_out?(status_data) do
    backend_state = get_in(status_data, ["BackendState"])
    self_data = get_in(status_data, ["Self"])

    backend_state == "LoggedOut" or is_nil(self_data)
  end

  defp extract_vpn_info(status_data) do
    %{}
    |> maybe_put(:vpn_ip, get_tailscale_ip(status_data))
    |> maybe_put(:vpn_hostname, get_in(status_data, ["Self", "HostName"]))
  end

  defp get_tailscale_ip(status_data) do
    case get_in(status_data, ["Self", "TailscaleIPs"]) do
      [ip | _] when is_binary(ip) -> ip
      _ -> nil
    end
  end

  defp ensure_directories do
    ["/var/lib/tailscale", "/var/cache/tailscale", "/var/run/tailscale"]
    |> Enum.each(&File.mkdir_p!/1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
