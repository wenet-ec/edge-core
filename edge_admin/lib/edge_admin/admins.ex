# edge_admin/lib/edge_admin/admins.ex
defmodule EdgeAdmin.Admins do
  @moduledoc """
  Public surface for admin-domain queries.

  Wraps `EdgeAdmin.Vpn` and other lower-level modules with operations whose
  inputs and outputs are expressed in admin-domain language (admin clusters,
  admin members) rather than raw Netmaker shapes.

  Membership/Metadata/Discovery remain their own modules — this is the
  cross-cutting facade for callers (controllers, MCP tools) that need
  admin-domain views derived from Netmaker data.
  """

  alias EdgeAdmin.Vpn

  @doc """
  Lists every admin cluster Netmaker knows about, with a normalised view of
  each cluster's admins.

  Includes admins this instance is not a member of (cross-cluster visibility)
  and may include stale entries — callers wanting health-only views should
  filter on `:status`.

  Shape:

      {:ok, [
        %{
          name: "admin-cluster-main",
          ipv4_range: "100.64.0.0/24",
          admin_count: 3,
          admins: [
            %{
              name: "admin-7k3m9p2n",
              vpn_hostname: "admin-7k3m9p2n.admin-cluster-main.nm.internal",
              netmaker_host_id: "f272e703-...",
              ipv4_address: "100.64.0.1",
              wireguard_ip_address: "10.0.0.7",
              wireguard_port: 51820,
              use_static_port: true,
              status: "online",
              last_checked_in: "2026-04-28T12:34:56Z"
            },
            ...
          ]
        },
        ...
      ]}

  Returns `{:error, :service_unavailable}` if Netmaker is unreachable.
  """
  @spec list_admin_clusters() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_admin_clusters do
    with {:ok, raw_clusters} <- Vpn.list_admin_cluster_networks() do
      {:ok, Enum.map(raw_clusters, &normalise_cluster/1)}
    end
  end

  # ===========================================================================
  # Normalisation
  # ===========================================================================

  defp normalise_cluster(%{network: network, members: members}) do
    cluster_name = network["netid"]

    admins =
      members
      |> Enum.map(&normalise_member(&1, cluster_name))
      |> Enum.sort_by(& &1.name)

    %{
      name: cluster_name,
      ipv4_range: network["addressrange"],
      admin_count: length(admins),
      admins: admins
    }
  end

  defp normalise_member(%{node: node, host: host}, cluster_name) do
    host_name = host["name"]

    %{
      name: host_name,
      vpn_hostname: Vpn.build_vpn_hostname(host_name, cluster_name),
      netmaker_host_id: host["id"],
      ipv4_address: strip_cidr(node["address"]),
      wireguard_ip_address: host["endpointip"],
      wireguard_port: host["listenport"],
      use_static_port: host["isstaticport"] == true,
      status: node["status"],
      last_checked_in: format_checkin(node["lastcheckin"])
    }
  end

  # Netmaker returns addresses as "100.64.0.1/24"; the cluster-level
  # `ipv4_range` already carries the prefix, so members expose just the IP.
  defp strip_cidr(nil), do: nil

  defp strip_cidr(address) when is_binary(address) do
    case String.split(address, "/", parts: 2) do
      [ip, _prefix] -> ip
      [ip] -> ip
    end
  end

  # Netmaker exposes lastcheckin as a Unix epoch (seconds). Format as ISO 8601
  # so consumers don't have to re-derive a timezone-aware timestamp.
  defp format_checkin(seconds) when is_integer(seconds) and seconds > 0 do
    seconds
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end

  defp format_checkin(_), do: nil
end
