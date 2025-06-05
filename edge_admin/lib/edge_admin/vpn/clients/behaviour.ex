# lib/edge_admin/vpn/clients/behaviour.ex
defmodule EdgeAdmin.VPN.Clients.Behaviour do
  @moduledoc """
  Behaviour for VPN client implementations.

  This behaviour defines the interface that all VPN clients must implement,
  allowing EdgeAdmin to work with different VPN technologies (Tailscale, Netmaker, etc.)
  without changing the core VPN context logic.

  Each client is responsible for implementing their own connectivity checking strategy,
  which may include multiple fallback checks, health endpoints, CLI tools, etc.
  """

  @doc """
  Checks if the VPN connection is active and healthy.

  Clients should implement their own strategy for checking connectivity.
  This may include:
  - Health check endpoints
  - CLI status commands
  - Peer connectivity tests
  - Management API calls

  Returns:
  - `:ok` - Connected and healthy
  - `{:ok, vpn_info}` - Connected with additional VPN information (IP, hostname, etc.)
  - `{:error, reason}` - Connection failed or unhealthy
  """
  @callback check_connectivity() :: :ok | {:ok, map()} | {:error, String.t()}

  @doc """
  Establishes a VPN connection.

  Should handle the full connection process including authentication,
  configuration, and any necessary setup steps.

  Returns:
  - `:ok` - Successfully connected
  - `{:ok, vpn_info}` - Successfully connected with VPN information
  - `{:error, reason}` - Connection failed
  """
  @callback connect_to_vpn() :: :ok | {:ok, map()} | {:error, String.t()}

  @doc """
  Disconnects from the VPN.

  Should cleanly terminate the VPN connection and cleanup any resources.

  Returns:
  - `:ok` - Successfully disconnected
  - `{:error, reason}` - Disconnection failed
  """
  @callback disconnect_from_vpn() :: :ok | {:error, String.t()}
end
