# edge_admin/lib/edge_admin_web/controllers/vpn/connection_json.ex
defmodule EdgeAdminWeb.VPN.ConnectionJSON do
  @moduledoc """
  JSON rendering for VPN connection resources.
  """

  alias Tailscale.Connection

  @doc """
  Renders a single VPN connection.
  """
  def show(%{connection: connection}) do
    %{data: data(connection)}
  end

  defp data(%Connection{} = connection) do
    %{
      status: connection.status,
      vpn_ip: connection.vpn_ip,
      vpn_hostname: connection.vpn_hostname,
      connected_at: connection.connected_at,
      last_checked_at: connection.last_checked_at,
      last_error: connection.last_error,
      last_error_at: connection.last_error_at,
      manual_disconnect: connection.manual_disconnect,
      inserted_at: connection.inserted_at,
      updated_at: connection.updated_at
    }
  end
end
