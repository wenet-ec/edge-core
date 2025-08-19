# edge_admin/lib/edge_admin/bootstrap.ex
defmodule EdgeAdmin.Bootstrap do
  @moduledoc """
  Bootstrap module for EdgeAdmin initialization.

  Handles the EdgeAdmin startup sequence:
  1. Setup VPN connection using enrollment key or existing state
  2. Any other admin-specific initialization

  Returns {:ok, :bootstrap_complete} on success or {:error, reason} on failure.

  ## Testability

  This module is designed to be testable by:
  - Allowing dependency injection via options
  - Supporting configurable VPN module
  - Graceful handling of missing environment variables
  - Clear separation of concerns between steps
  """

  alias EdgeAdmin.VPN

  require Logger

  @doc """
  Runs the complete bootstrap sequence.

  ## Options

  * `:vpn_module` - Module to use for VPN operations (default: `EdgeAdmin.VPN`)
  * `:env_provider` - Function to get environment variables (default: `&System.get_env/1`)
  * `:skip_vpn` - Whether to skip VPN setup (default: `false`)

  ## Examples

      # Normal production use
      Bootstrap.run()

      # Test with mocked dependencies
      Bootstrap.run(vpn_module: MyMock, env_provider: fn _ -> "test-value" end)

      # Skip VPN for integration tests
      Bootstrap.run(skip_vpn: true)
  """
  def run(opts \\ []) do
    Logger.info("Starting EdgeAdmin bootstrap...")

    _vpn_module = Keyword.get(opts, :vpn_module, VPN)
    skip_vpn = Keyword.get(opts, :skip_vpn, false)

    result =
      if skip_vpn do
        Logger.info("Skipping VPN setup as requested")
        :ok
      else
        setup_vpn_connection(opts)
      end

    case result do
      :ok ->
        Logger.info("EdgeAdmin bootstrap sequence completed successfully")
        {:ok, :bootstrap_complete}

      {:error, reason} = error ->
        Logger.error("EdgeAdmin bootstrap sequence failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Sets up VPN connection with configurable dependencies.

  ## Options

  * `:vpn_module` - Module to use for VPN operations
  * `:env_provider` - Function to get environment variables
  * `:vpn_url` - Override VPN URL (for testing)
  * `:enrollment_key` - Override enrollment key (for testing)
  """
  def setup_vpn_connection(opts \\ []) do
    Logger.info("Setting up VPN connection for EdgeAdmin...")

    vpn_module = Keyword.get(opts, :vpn_module, VPN)
    env_provider = Keyword.get(opts, :env_provider, &System.get_env/1)

    # Get credentials - allow override for testing
    vpn_url = Keyword.get(opts, :vpn_url) || env_provider.("VPN_URL")
    enrollment_key = Keyword.get(opts, :enrollment_key) || env_provider.("ENROLLMENT_KEY")

    with :ok <- vpn_module.start_daemon(),
         {:ok, _result} <- vpn_module.connect_to_vpn(vpn_url, enrollment_key, "edge-admin"),
         {:ok, vpn_ip} <- validate_vpn_connection(vpn_module),
         {:ok, _connection} <- vpn_module.sync_connection_state() do
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
  defp validate_vpn_connection(vpn_module) do
    case vpn_module.get_vpn_ip() do
      {:ok, ip} when is_binary(ip) ->
        {:ok, ip}

      {:error, reason} ->
        {:error, "VPN connection validation failed: #{inspect(reason)}"}
    end
  end
end
