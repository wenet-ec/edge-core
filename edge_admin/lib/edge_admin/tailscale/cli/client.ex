# edge_admin/lib/edge_admin/tailscale/cli/client.ex
defmodule EdgeAdmin.Tailscale.Cli.Client do
  @moduledoc """
  Tailscale CLI client for managing VPN connections using enrollment keys.

  This module handles direct interaction with the Tailscale command-line interface
  for connection management, status checking, and daemon control.
  """

  @behaviour EdgeAdmin.Tailscale.Cli.Behaviour

  require Logger

  @type connection_result :: {:ok, map()} | {:ok, :no_info} | {:error, String.t()}
  @type connectivity_result :: {:ok, map()} | {:ok, :healthy} | {:error, String.t()}

  @tailscale_state_dir "/var/lib/tailscale"
  @tailscale_state_file "/var/lib/tailscale/tailscaled.state"
  @tailscale_socket "/var/run/tailscale/tailscaled.sock"
  @tailscale_cache_dir "/var/cache/tailscale"

  @impl true
  def connect_to_vpn(vpn_url, enrollment_key, hostname) do
    Logger.info("Tailscale CLI: Initiating connection to #{vpn_url} with hostname #{hostname}")

    with :ok <- ensure_daemon_running(),
         :ok <- perform_connection_with_key(vpn_url, enrollment_key, hostname),
         result <- get_connection_info() do
      Logger.info("Tailscale CLI: Connection flow completed successfully")
      result
    else
      {:error, reason} = error ->
        Logger.error("Tailscale CLI: Connection flow failed - #{reason}")
        error
    end
  end

  @impl true
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

  @impl true
  def disconnect_from_vpn do
    Logger.info("Tailscale CLI: Initiating disconnection")

    case System.cmd("tailscale", ["down"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Tailscale CLI: Disconnected successfully")
        :ok

      {output, _code} ->
        error_msg = "Disconnect failed: #{String.trim(output)}"
        Logger.error("Tailscale CLI: #{error_msg}")
        {:error, error_msg}
    end
  rescue
    e ->
      error_msg = "Disconnect failed: #{inspect(e)}"
      Logger.error("Tailscale CLI: #{error_msg}")
      {:error, error_msg}
  end

  @impl true
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

  @impl true
  def connected?(status_data) when is_map(status_data) do
    backend_state = get_in(status_data, ["BackendState"])
    self_online = get_in(status_data, ["Self", "Online"])

    backend_state in ["Running", "Starting"] and self_online == true and
      not logged_out?(status_data)
  end

  def connected?(_), do: false

  @impl true
  def start_daemon do
    Logger.info("Tailscale CLI: Starting daemon...")

    ensure_directories()

    cmd = "tailscaled --state=#{@tailscale_state_file} --socket=#{@tailscale_socket}"

    spawn(fn ->
      System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)
    end)

    :timer.sleep(2000)
    Logger.info("Tailscale CLI: Daemon started")
    :ok
  end

  @impl true
  def get_vpn_ip do
    case status_json() do
      {:ok, status_data} ->
        case get_tailscale_ip(status_data) do
          nil -> {:error, :no_ip}
          ip -> {:ok, ip}
        end

      {:error, _} ->
        {:error, :status_failed}
    end
  end

  # Private functions

  defp ensure_daemon_running do
    case System.cmd("tailscale", ["status"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.debug("Tailscale CLI: Daemon already running")
        :ok

      {_output, _} ->
        Logger.info("Tailscale CLI: Starting daemon")
        start_daemon()
    end
  end

  defp ensure_directories do
    [@tailscale_state_dir, @tailscale_cache_dir, "/var/run/tailscale"]
    |> Enum.each(&File.mkdir_p!/1)
  end

  defp perform_connection_with_key(vpn_url, enrollment_key, hostname) do
    if already_connected?(hostname) do
      Logger.info("Tailscale CLI: Already connected with hostname #{hostname}")
      :ok
    else
      connect_with_state_check(vpn_url, enrollment_key, hostname)
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

  defp connect_with_state_check(vpn_url, enrollment_key, hostname) do
    if File.exists?(@tailscale_state_file) and File.stat!(@tailscale_state_file).size > 0 do
      Logger.info("Tailscale CLI: Found existing state, checking if it's valid...")
      :timer.sleep(2000)

      case System.cmd("tailscale", ["status"], stderr_to_stdout: true) do
        {output, 0} ->
          cond do
            String.contains?(output, "Logged out") ->
              Logger.info(
                "Tailscale CLI: Existing state is logged out, using new enrollment key..."
              )

              fresh_connect_with_key(vpn_url, enrollment_key, hostname)

            String.contains?(output, hostname) ->
              Logger.info(
                "Tailscale CLI: Found valid existing authentication, attempting to connect..."
              )

              attempt_reconnect_with_fallback(vpn_url, hostname, enrollment_key)

            true ->
              Logger.info("Tailscale CLI: Unknown state, using new enrollment key...")
              fresh_connect_with_key(vpn_url, enrollment_key, hostname)
          end

        {output, _exit_code} ->
          Logger.info(
            "Tailscale CLI: Cannot get status (#{String.trim(output)}), using new enrollment key..."
          )

          fresh_connect_with_key(vpn_url, enrollment_key, hostname)
      end
    else
      Logger.info("Tailscale CLI: No existing state, using enrollment key...")
      fresh_connect_with_key(vpn_url, enrollment_key, hostname)
    end
  end

  defp attempt_reconnect_with_fallback(vpn_url, hostname, fallback_key) do
    args = ["up", "--login-server=#{vpn_url}", "--accept-dns=false", "--hostname=#{hostname}"]

    case System.cmd("tailscale", args, stderr_to_stdout: true) do
      {_output, 0} ->
        :timer.sleep(2000)

        if verify_connection() do
          Logger.info("Tailscale CLI: Successfully reconnected using existing credentials")
          :ok
        else
          Logger.info(
            "Tailscale CLI: Failed to reconnect with existing state, will use new enrollment key..."
          )

          fresh_connect_with_key(vpn_url, fallback_key, hostname)
        end

      {_output, _} ->
        Logger.info(
          "Tailscale CLI: Failed to reconnect with existing state, will use new enrollment key..."
        )

        fresh_connect_with_key(vpn_url, fallback_key, hostname)
    end
  end

  defp fresh_connect_with_key(vpn_url, enrollment_key, hostname) do
    Logger.info("Tailscale CLI: Connecting to VPN with enrollment key...")

    args = [
      "up",
      "--login-server=#{vpn_url}",
      "--authkey=#{enrollment_key}",
      "--accept-dns=false",
      "--hostname=#{hostname}"
    ]

    case System.cmd("tailscale", args, stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Tailscale CLI: Successfully connected to VPN")
        :ok

      {output, exit_code} ->
        error_msg = "Connection failed: #{String.trim(output)} (exit code: #{exit_code})"
        Logger.error("Tailscale CLI: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp get_connection_info do
    case check_connectivity() do
      {:ok, info} when is_map(info) -> {:ok, info}
      {:ok, :healthy} -> {:ok, :no_info}
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
