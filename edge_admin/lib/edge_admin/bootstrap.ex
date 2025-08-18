# edge_admin/lib/edge_admin/bootstrap.ex
defmodule EdgeAdmin.Bootstrap do
  @moduledoc """
  Bootstrap module for EdgeAdmin initialization.

  Handles the EdgeAdmin startup sequence:
  1. Setup VPN connection using enrollment key or existing state
  2. Any other admin-specific initialization

  Returns {:ok, :bootstrap_complete} on success or {:error, reason} on failure.
  """

  require Logger

  alias EdgeAdmin.VPN

  def run do
    Logger.info("Starting EdgeAdmin bootstrap...")

    with :ok <- setup_vpn_connection() do
      Logger.info("EdgeAdmin bootstrap sequence completed successfully")
      {:ok, :bootstrap_complete}
    else
      {:error, reason} = error ->
        Logger.error("EdgeAdmin bootstrap sequence failed: #{inspect(reason)}")
        error
    end
  end

  def setup_vpn_connection do
    Logger.info("Setting up VPN connection for EdgeAdmin...")

    # Get credentials but don't fail if they're missing
    vpn_url = System.get_env("VPN_URL")
    enrollment_key = System.get_env("ENROLLMENT_KEY")

    with :ok <- VPN.start_daemon(),
         {:ok, _result} <- VPN.connect_to_vpn(vpn_url, enrollment_key, "edge-admin"),
         {:ok, vpn_ip} <- validate_vpn_connection(),
         {:ok, _connection} <- VPN.sync_connection_state() do
      Logger.info("Successfully connected to VPN with IP: #{vpn_ip}")
      Logger.info("VPN connection state synchronized")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("VPN connection failed: #{inspect(reason)}")
        error
    end
  end

  # Validate VPN connection is working
  defp validate_vpn_connection do
    case VPN.get_vpn_ip() do
      {:ok, ip} when is_binary(ip) ->
        {:ok, ip}

      {:error, reason} ->
        {:error, "VPN connection validation failed: #{inspect(reason)}"}
    end
  end
end
