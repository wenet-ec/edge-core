# edge_admin/lib/edge_admin/vpn.ex
defmodule EdgeAdmin.VPN do
  @moduledoc """
  VPN context for EdgeAdmin.

  This module provides EdgeAdmin-specific VPN functionality while delegating
  core operations to the shared Tailscale library. It handles EdgeAdmin's
  specific hostname requirements, environment configuration, and business logic.
  """

  alias EdgeAdmin.VPN.Connection

  require Logger

  # Module configuration - allows dependency injection for testing
  defp tailscale_module do
    Application.get_env(:edge_admin, :tailscale_module, Tailscale)
  end

  # Delegate all basic operations to the configured library (real or mock)
  def connect_to_vpn(vpn_url, enrollment_key, hostname),
    do: tailscale_module().connect_to_vpn(vpn_url, enrollment_key, hostname)

  def disconnect_from_vpn, do: tailscale_module().disconnect_from_vpn()

  def check_connectivity, do: tailscale_module().check_connectivity()

  def status_json, do: tailscale_module().status_json()

  def connected?(status_data), do: tailscale_module().connected?(status_data)

  def start_daemon, do: tailscale_module().start_daemon()

  def get_vpn_ip, do: tailscale_module().get_vpn_ip()

  def get_node_by_hostname(vpn_hostname), do: tailscale_module().get_node_by_hostname(vpn_hostname)

  def list_nodes_for_user(user \\ "edge-nodes"), do: tailscale_module().list_nodes_for_user(user)

  def create_enrollment_key(user \\ "edge-nodes"), do: tailscale_module().create_enrollment_key(user)

  def get_user(username), do: tailscale_module().get_user(username)

  def get_connection, do: tailscale_module().get_connection()

  def create_connection(attrs \\ %{}), do: tailscale_module().create_connection(attrs)

  def get_connection!, do: tailscale_module().get_connection!()

  def check_and_update_connectivity, do: tailscale_module().check_and_update_connectivity()

  def sync_connection_state, do: tailscale_module().sync_connection_state()

  def disconnect_from_vpn_manual, do: tailscale_module().disconnect_from_vpn_manual()

  # EdgeAdmin-specific hostname provider
  defp hostname_provider, do: "edge-admin"

  # EdgeAdmin-specific business logic functions

  @doc """
  Updates the VPN connection with the given attributes.
  """
  def update_connection(attrs) do
    connection = get_connection!()
    tailscale_module().update_connection(connection, attrs)
  end

  @doc """
  Updates VPN connection from controller parameters with changeset validation.

  This function uses Ecto changesets for validation and provides detailed error information.
  """
  def update_connection_from_params(params) do
    with {:ok, tailscale_conn} <- get_connection() do
      embedded_conn = Connection.from_tailscale_connection(tailscale_conn)
      changeset = Connection.update_changeset(embedded_conn, params)

      if changeset.valid? do
        case Ecto.Changeset.get_change(changeset, :manual_disconnect) do
          true ->
            Logger.info("VPN: Performing manual disconnect")

            case disconnect_from_vpn_manual() do
              {:ok, updated_tailscale_conn} ->
                {:ok, Connection.from_tailscale_connection(updated_tailscale_conn)}

              error ->
                error
            end

          false ->
            Logger.info("VPN: Re-enabling auto-reconnection")

            case update_connection(%{manual_disconnect: false}) do
              {:ok, updated_tailscale_conn} ->
                {:ok, Connection.from_tailscale_connection(updated_tailscale_conn)}

              error ->
                error
            end

          nil ->
            {:ok, Connection.from_tailscale_connection(tailscale_conn)}
        end
      else
        {:error, changeset}
      end
    end
  end

  @doc """
  Updates the VPN connection with manual disconnect handling.

  This function encapsulates the business logic for updating VPN connections:
  - When manual_disconnect is true: Performs immediate disconnect
  - When manual_disconnect is false: Updates flag to allow auto-reconnection
  """
  def update_connection_manual_disconnect(manual_disconnect) when is_boolean(manual_disconnect) do
    if manual_disconnect do
      Logger.info("VPN: Performing manual disconnect")
      disconnect_from_vpn_manual()
    else
      Logger.info("VPN: Re-enabling auto-reconnection")
      update_connection(%{manual_disconnect: false})
    end
  end

  @doc """
  Attempts auto-reconnection using EdgeAdmin-specific configuration.
  """
  def attempt_auto_reconnection do
    tailscale_module().attempt_auto_reconnection(vpn_url(), enrollment_key(), hostname_provider())
  end

  @doc """
  Initiates manual connection using EdgeAdmin-specific configuration.
  """
  def connect_to_vpn_manual do
    tailscale_module().connect_to_vpn_manual(vpn_url(), enrollment_key(), hostname_provider())
  end

  @doc """
  Creates enrollment key with proper error handling and user-friendly messages.

  This function encapsulates the business logic for enrollment key creation including
  error classification and message formatting.
  """
  def create_enrollment_key_with_error_handling do
    case create_enrollment_key() do
      {:ok, enrollment_data} ->
        {:ok, enrollment_data}

      {:error, :vpn_service_unavailable} ->
        {:error, :vpn_service_unavailable, "VPN service is currently unavailable"}

      {:error, :user_not_found} ->
        {:error, :internal_server_error, "edge-nodes user not found in VPN system"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Connection data transformation

  @doc """
  Transforms a Tailscale.Connection struct into an EdgeAdmin.VPN.Connection embedded schema.
  """
  def get_connection_as_embedded do
    case get_connection() do
      {:ok, tailscale_conn} -> {:ok, Connection.from_tailscale_connection(tailscale_conn)}
      error -> error
    end
  end

  # Private helper functions

  defp vpn_url do
    Application.get_env(:edge_admin, :vpn_url) ||
      System.get_env("VPN_URL") ||
      raise "VPN_URL environment variable not set"
  end

  defp enrollment_key do
    Application.get_env(:edge_admin, :enrollment_key) ||
      System.get_env("ENROLLMENT_KEY") ||
      raise "ENROLLMENT_KEY environment variable not set"
  end
end
