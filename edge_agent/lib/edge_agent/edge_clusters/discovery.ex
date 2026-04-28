# edge_agent/lib/edge_agent/edge_clusters/discovery.ex
defmodule EdgeAgent.EdgeClusters.Discovery do
  @moduledoc """
  Admin server discovery via WireGuard peer inspection.

  Discovers admin servers on the VPN network by inspecting WireGuard peers
  and querying their discovery endpoints. More efficient than subnet scanning
  since we directly query known peers instead of scanning entire CIDR blocks.

  ## Discovery Process

  ```
  1. Query WireGuard for peer list (netclient ping)
  2. Filter peers whose name starts with "admin-"
  3. HTTP GET http://ip:port/api/v1/admins/me/discovery on each candidate
  4. Store confirmed admin URLs (http://ip:port) in Settings for AdminClient
  ```

  ## Discovery Behavior

  - Always returns `{:ok, network_name | nil, admin_urls}` - never fails
  - Stores results (even empty list) in Settings to signal discovery completion
  - Empty list indicates VPN is up but no admins found (triggers HTTP fallback mode)

  ## Admin Discovery Endpoint

  Admins expose `/api/v1/admins/me/discovery` returning:
  ```json
  {"data": {"name": "admin-abc123"}}
  ```

  ## Examples

      iex> Discovery.discover_admins()
      {:ok, "cluster-default", ["http://100.64.0.4:44000"]}

      iex> Discovery.discover_admins()
      {:ok, nil, []}

      iex> Discovery.discover_admins()
      {:ok, "cluster-prod", ["http://100.64.0.4:44000", "http://100.64.0.5:44000"]}
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  require Logger

  @doc """
  Discover admins in the cluster.

  Returns `{:ok, network_name, admin_urls}` where network_name is the Netmaker
  network name (e.g. "cluster-default") or nil if none found, and admin_urls is
  a list of HTTP URLs using VPN IPs (e.g. ["http://100.64.0.4:44000"]).

  Always stores discovered admins (even empty list) in Settings so other
  components can distinguish "never discovered" from "discovered but none found".
  """
  @spec discover_admins(keyword()) :: {:ok, String.t() | nil, [String.t()]}
  def discover_admins(_opts \\ []) do
    network_name = get_network_name_from_list()

    case EdgeAgent.Vpn.ping_peers() do
      {:ok, ping_data} when map_size(ping_data) == 0 ->
        Logger.warning("No peers found on any network")
        Settings.set_admin_urls([])
        {:ok, network_name, []}

      {:ok, ping_data} ->
        Logger.info("Inspecting peers on #{map_size(ping_data)} network(s) for admins...")

        discovery_port = Application.get_env(:edge_agent, :admin_discovery_port, 44_000)

        {found_network, admin_urls} =
          Enum.reduce(ping_data, {nil, []}, fn {net_name, peers}, {_net, acc_urls} ->
            urls = Enum.flat_map(peers, &probe_peer(&1, net_name, discovery_port))
            {net_name, acc_urls ++ urls}
          end)

        admin_urls = Enum.uniq(admin_urls)

        if admin_urls == [] do
          Logger.warning("No admins discovered across any network")
          result_network = found_network || network_name
          Settings.set_admin_urls([])
          {:ok, result_network, []}
        else
          Logger.info("Discovered #{length(admin_urls)} unique admin(s) across all networks")
          Settings.set_admin_urls(admin_urls)
          {:ok, found_network, admin_urls}
        end

      {:error, reason} ->
        Logger.error("Failed to ping peers: #{inspect(reason)}")
        Settings.set_admin_urls([])
        {:ok, network_name, []}
    end
  end

  defp get_network_name_from_list do
    case EdgeAgent.Vpn.list_networks() do
      {:ok, [first | _]} -> first["network"]
      _ -> nil
    end
  end

  # Returns a list of 0 or 1 admin URL for this peer
  defp probe_peer(%{"name" => "admin-" <> _, "address" => ip}, network_name, port) when is_binary(ip) do
    base_url = "http://#{ip}:#{port}"

    case AdminClient.probe(base_url) do
      {:ok, admin_name} ->
        Logger.info("✓ Discovered admin: #{admin_name} (#{ip}) on #{network_name}")
        [base_url]

      {:error, :unexpected_body} ->
        Logger.debug("✗ #{ip} on #{network_name} returned 200 but unexpected body shape")
        []

      {:error, {:http_error, status}} ->
        Logger.debug("✗ #{ip} on #{network_name} returned status #{status}")
        []

      {:error, reason} ->
        Logger.debug("✗ #{ip} on #{network_name} HTTP failed: #{inspect(reason)}")
        []
    end
  end

  defp probe_peer(peer, network_name, _port) do
    Logger.debug("✗ Skipping peer on #{network_name} (not admin or no IP): #{inspect(peer)}")
    []
  end
end
