# lib/edge_admin/vpn/config.ex
defmodule EdgeAdmin.VPN.Config do
  @moduledoc """
  Configuration for VPN context.
  """

  def client_module do
    Application.fetch_env!(:edge_admin, :vpn)[:client]
  end

  def vpn_url do
    EdgeAdmin.Config.get_env!("VPN_URL")
  end
end
