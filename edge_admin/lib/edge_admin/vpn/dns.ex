# edge_admin/lib/edge_admin/vpn/dns.ex
defmodule EdgeAdmin.Vpn.Dns do
  @moduledoc "Custom Edge VPN DNS record operations."

  alias EdgeAdmin.Vpn.Api, as: VpnApi
  alias Nexmaker.Api.DNS, as: NexmakerDns

  @spec create_dns_entry(String.t(), map()) :: {:ok, map()} | {:error, :service_unavailable}
  def create_dns_entry(network_name, attrs), do: network_name |> NexmakerDns.create(attrs) |> VpnApi.normalize_error()

  @spec list_custom_dns_entries(String.t()) :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_custom_dns_entries(network_name),
    do: network_name |> NexmakerDns.list_custom_entries() |> VpnApi.normalize_error()

  @spec delete_dns_entry(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_dns_entry(network_name, dns_name),
    do: network_name |> NexmakerDns.delete(dns_name) |> VpnApi.normalize_error()
end
