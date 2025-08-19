# edge_admin/test/support/mocks/tailscale_behaviour.ex
defmodule EdgeAdmin.TailscaleBehaviour do
  @moduledoc """
  Behaviour defining the interface for Tailscale module operations.

  This behaviour allows us to swap the real Tailscale implementation
  with mocks during testing, ensuring we test our business logic
  without depending on external VPN services.
  """

  @doc "Connect to VPN with given URL, enrollment key and hostname"
  @callback connect_to_vpn(vpn_url :: String.t(), enrollment_key :: String.t(), hostname :: String.t()) ::
              {:ok, map()} | {:error, atom() | String.t()}

  @doc "Disconnect from VPN"
  @callback disconnect_from_vpn() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Check VPN connectivity status"
  @callback check_connectivity() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Get VPN status as JSON"
  @callback status_json() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Check if connected based on status data"
  @callback connected?(status_data :: map()) :: boolean()

  @doc "Start Tailscale daemon"
  @callback start_daemon() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Get current VPN IP address"
  @callback get_vpn_ip() :: {:ok, String.t()} | {:error, atom() | String.t()}

  @doc "Get node by hostname from VPN"
  @callback get_node_by_hostname(hostname :: String.t()) :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "List all nodes for a given user"
  @callback list_nodes_for_user(user :: String.t()) :: {:ok, [map()]} | {:error, atom() | String.t()}

  @doc "Create enrollment key for a user"
  @callback create_enrollment_key(user :: String.t()) :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Get user information"
  @callback get_user(username :: String.t()) :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Get current connection state"
  @callback get_connection() :: {:ok, Tailscale.Connection.t()} | {:error, atom() | String.t()}

  @doc "Create a new connection with attributes"
  @callback create_connection(attrs :: map()) :: {:ok, Tailscale.Connection.t()} | {:error, atom() | String.t()}

  @doc "Get current connection state (raises on error)"
  @callback get_connection!() :: Tailscale.Connection.t()

  @doc "Update connection with new attributes"
  @callback update_connection(connection :: Tailscale.Connection.t(), attrs :: map()) ::
              {:ok, Tailscale.Connection.t()} | {:error, atom() | String.t()}

  @doc "Check and update connectivity status"
  @callback check_and_update_connectivity() :: {:ok, Tailscale.Connection.t()} | {:error, atom() | String.t()}

  @doc "Synchronize connection state"
  @callback sync_connection_state() :: {:ok, map()} | {:error, atom() | String.t()}

  @doc "Manually disconnect from VPN"
  @callback disconnect_from_vpn_manual() :: {:ok, Tailscale.Connection.t()} | {:error, atom() | String.t()}

  @doc "Manually connect to VPN"
  @callback connect_to_vpn_manual(vpn_url :: String.t(), enrollment_key :: String.t(), hostname :: String.t()) ::
              {:ok, Tailscale.Connection.t()} | {:error, atom() | String.t()}

  @doc "Attempt auto-reconnection to VPN"
  @callback attempt_auto_reconnection(vpn_url :: String.t(), enrollment_key :: String.t(), hostname :: String.t()) ::
              {:ok, map()} | {:error, atom() | String.t()}
end
