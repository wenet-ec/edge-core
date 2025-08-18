# edge_admin/lib/edge_admin_web/controllers/vpn/connection_json.ex
defmodule EdgeAdminWeb.VPN.ConnectionJSON do
  @moduledoc """
  JSON rendering for VPN connection resources.
  """

  alias EdgeAdmin.VPN
  alias Tailscale.Connection

  @doc """
  Renders a single VPN connection.
  """
  def show(%{connection: connection}) do
    %{data: data(connection)}
  end

  defp data(%Connection{} = connection) do
    VPN.connection_to_map(connection)
  end
end
