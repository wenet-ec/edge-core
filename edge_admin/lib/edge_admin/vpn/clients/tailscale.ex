# lib/edge_admin/vpn/clients/tailscale.ex
defmodule EdgeAdmin.VPN.Clients.Tailscale do
  @moduledoc """
  Tailscale VPN client implementation.

  Uses Tailscale CLI as the single source of truth for all VPN state checks.
  The CLI provides authoritative information about connection status, IPs,
  and other VPN details directly from the VPN client itself.
  """

  @behaviour EdgeAdmin.VPN.Clients.Behaviour

  alias EdgeAdmin.VPN.Config, as: VPNConfig

  require Logger

  @impl EdgeAdmin.VPN.Clients.Behaviour
  def check_connectivity do
    check_vpn_status()
  end

  @impl EdgeAdmin.VPN.Clients.Behaviour
  def connect_to_vpn do
    Logger.info("Tailscale: Initiating VPN connection")

    # First check if we're already connected
    case check_connectivity() do
      :ok ->
        Logger.info("Tailscale: Already connected")
        {:ok, %{}}

      {:ok, vpn_info} ->
        Logger.info("Tailscale: Already connected with VPN info")
        {:ok, vpn_info}

      {:error, _} ->
        Logger.debug("Tailscale: Not connected, attempting connection")
        attempt_vpn_connection()
    end
  rescue
    e ->
      error_msg = "Tailscale connect_to_vpn failed: #{inspect(e)}"
      Logger.error(error_msg)
      {:error, error_msg}
  end

  @impl EdgeAdmin.VPN.Clients.Behaviour
  def disconnect_from_vpn do
    Logger.info("Tailscale: Initiating VPN disconnection")

    case System.cmd("tailscale", ["down"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Tailscale: Disconnected successfully")
        :ok

      {output, _code} ->
        error_msg = "Failed to disconnect: #{String.trim(output)}"
        Logger.error("Tailscale: #{error_msg}")
        {:error, error_msg}
    end
  rescue
    e ->
      error_msg = "Tailscale disconnect failed: #{inspect(e)}"
      Logger.error(error_msg)
      {:error, error_msg}
  end

  # Private helper functions

  defp check_vpn_status do
    case System.cmd("tailscale", ["status", "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, status_data} ->
            if is_connected?(status_data) do
              vpn_info = extract_vpn_info(status_data)

              if map_size(vpn_info) > 0 do
                {:ok, vpn_info}
              else
                :ok
              end
            else
              {:error, "Tailscale not connected"}
            end

          {:error, _decode_error} ->
            # JSON decode failed, but exit code was 0, so probably connected
            :ok
        end

      {output, _code} ->
        {:error, "Tailscale CLI error: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "Tailscale execution failed: #{inspect(e)}"}
  end

  defp attempt_vpn_connection do
    vpn_url = VPNConfig.vpn_url()

    case System.cmd(
           "tailscale",
           ["up", "--login-server=#{vpn_url}", "--accept-dns=false", "--hostname=edge-admin"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Tailscale: Connection command succeeded")

        # Wait for connection to establish
        :timer.sleep(2000)

        # Verify connection and get info
        case check_vpn_status() do
          {:ok, vpn_info} ->
            Logger.info("Tailscale: Connected successfully with VPN info")
            {:ok, vpn_info}

          :ok ->
            Logger.info("Tailscale: Connected successfully")
            {:ok, %{}}

          {:error, reason} ->
            Logger.warning("Tailscale: Connection command succeeded but status check failed: #{reason}")

            # Return success anyway since the command succeeded
            {:ok, %{}}
        end

      {output, _code} ->
        error_msg = "Failed to connect: #{String.trim(output)}"
        Logger.error("Tailscale: #{error_msg}")
        {:error, error_msg}
    end
  end

  defp is_connected?(status_data) do
    # Check if we have a valid BackendState indicating connection
    backend_state = get_in(status_data, ["BackendState"])
    backend_state in ["Running", "Starting"] and not is_logged_out?(status_data)
  end

  defp is_logged_out?(status_data) do
    # Check various indicators that we're logged out
    backend_state = get_in(status_data, ["BackendState"])
    self_data = get_in(status_data, ["Self"])

    backend_state == "LoggedOut" or
      is_nil(self_data) or
      get_in(status_data, ["Self", "Online"]) == false
  end

  defp extract_vpn_info(status_data) do
    %{}
    |> maybe_put(:vpn_ip, get_tailscale_ip(status_data))
    |> maybe_put(:vpn_hostname, get_in(status_data, ["Self", "HostName"]))
  end

  defp get_tailscale_ip(status_data) do
    # Try to get the first Tailscale IP (usually IPv4)
    case get_in(status_data, ["Self", "TailscaleIPs"]) do
      [ip | _] when is_binary(ip) -> ip
      _ -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
