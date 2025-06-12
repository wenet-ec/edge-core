# lib/edge_agent/vpn/tailscale.ex
defmodule EdgeAgent.VPN.Tailscale do
  @moduledoc """
  Tailscale client for managing VPN connections on edge agents.
  """

  require Logger

  @tailscale_state_dir "/var/lib/tailscale"
  @tailscale_state_file "/var/lib/tailscale/tailscaled.state"
  @tailscale_socket "/var/run/tailscale/tailscaled.sock"
  @tailscale_cache_dir "/var/cache/tailscale"

  def start_daemon do
    Logger.info("Starting tailscaled daemon...")

    # Ensure directories exist (just like bash script)
    ensure_directories()

    # Start daemon in background using spawn - this replicates the & in bash
    cmd = "tailscaled --state=#{@tailscale_state_file} --socket=#{@tailscale_socket}"

    # Use spawn to start in background (equivalent to & in bash)
    spawn(fn ->
      System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)
    end)

    # Sleep 2 seconds just like bash script
    :timer.sleep(2000)
    Logger.info("Tailscaled daemon started")
    :ok
  end

  def connect(login_server, authkey, hostname) do
    Logger.info("Setting up VPN connection with hostname: #{hostname}")

    # Check if already connected (like bash script)
    case check_already_connected(hostname) do
      true ->
        Logger.info("Already authenticated and connected, using existing state")
        :ok
      false ->
        connect_with_state_check(login_server, authkey, hostname)
    end
  end

  def status do
    case System.cmd("tailscale", ["status"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}
      {_output, _exit_code} ->
        # Return error but don't log - this is used for checking
        {:error, :status_failed}
    end
  end

  def get_vpn_ip do
    case status() do
      {:ok, output} ->
        case Regex.run(~r/100\.\d+\.\d+\.\d+/, output) do
          [ip] -> {:ok, ip}
          nil -> {:error, :no_ip}
        end
      {:error, _} ->
        {:error, :status_failed}
    end
  end

  def is_connected? do
    case get_vpn_ip() do
      {:ok, _ip} -> true
      {:error, _} -> false
    end
  end

  # Private functions that replicate bash script logic

  defp ensure_directories do
    [@tailscale_state_dir, @tailscale_cache_dir, "/var/run/tailscale"]
    |> Enum.each(&File.mkdir_p!/1)
  end

  defp check_already_connected(hostname) do
    # Replicate: tailscale status 2>/dev/null | grep -q "hostname" && tailscale status 2>/dev/null | grep -q "100\."
    case status() do
      {:ok, output} ->
        has_hostname = String.contains?(output, hostname)
        has_vpn_ip = Regex.match?(~r/100\.\d+\.\d+\.\d+/, output)
        has_hostname && has_vpn_ip
      {:error, _} ->
        false
    end
  end

  defp connect_with_state_check(login_server, authkey, hostname) do
    # Check for existing state (like bash script)
    if File.exists?(@tailscale_state_file) and File.stat!(@tailscale_state_file).size > 0 do
      Logger.info("Found existing Tailscale state, checking if it's valid...")

      # Sleep 2 like bash script
      :timer.sleep(2000)

      case status() do
        {:ok, output} ->
          cond do
            String.contains?(output, "Logged out") ->
              Logger.info("Existing state is logged out, using new enrollment key...")
              fresh_connect(login_server, authkey, hostname)

            String.contains?(output, hostname) ->
              Logger.info("Found valid existing authentication, attempting to connect...")
              attempt_reconnect(login_server, hostname, authkey)

            true ->
              Logger.info("Unknown state, using new enrollment key...")
              fresh_connect(login_server, authkey, hostname)
          end
        {:error, _} ->
          Logger.info("Cannot get status, using new enrollment key...")
          fresh_connect(login_server, authkey, hostname)
      end
    else
      Logger.info("No existing state, using enrollment key...")
      fresh_connect(login_server, authkey, hostname)
    end
  end

  defp attempt_reconnect(login_server, hostname, fallback_authkey) do
    args = ["up", "--login-server=#{login_server}", "--accept-dns=false", "--hostname=#{hostname}"]

    case System.cmd("tailscale", args, stderr_to_stdout: true) do
      {_output, 0} ->
        :timer.sleep(2000)
        if is_connected?() do
          Logger.info("Successfully reconnected using existing credentials")
          :ok
        else
          Logger.info("Failed to reconnect with existing state, will use new enrollment key...")
          fresh_connect(login_server, fallback_authkey, hostname)
        end
      {_output, _} ->
        Logger.info("Failed to reconnect with existing state, will use new enrollment key...")
        fresh_connect(login_server, fallback_authkey, hostname)
    end
  end

  defp fresh_connect(login_server, authkey, hostname) do
    Logger.info("Connecting to VPN with enrollment key...")

    args = [
      "up",
      "--login-server=#{login_server}",
      "--authkey=#{authkey}",
      "--accept-dns=false",
      "--hostname=#{hostname}"
    ]

    case System.cmd("tailscale", args, stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Successfully connected to VPN")
        :ok
      {output, exit_code} ->
        Logger.error("Failed to connect to VPN: #{output} (exit code: #{exit_code})")
        :error
    end
  end
end
