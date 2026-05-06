# edge_agent/lib/edge_agent/edge_clusters/discovery.ex
defmodule EdgeAgent.EdgeClusters.Discovery do
  @moduledoc """
  Admin server discovery via WireGuard peer inspection.

  Discovers admin servers on the VPN network by listing WireGuard peers
  (via `netclient ping`) and probing the ones named `admin-*` on their
  discovery endpoint.

  ## Discovery Process

  ```
  1. List WireGuard peers per network via EdgeAgent.Vpn.ping_peers/0
  2. Filter peers whose name starts with "admin-"
  3. HTTP GET http://ip:port/api/v1/admins/me/discovery on each candidate
     in parallel (Task.async_stream)
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
      {:ok, "cluster-test", ["http://100.64.0.4:44000"]}

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
  network name (e.g. "cluster-test") or nil if none found, and admin_urls is
  a list of HTTP URLs using VPN IPs (e.g. ["http://100.64.0.4:44000"]).

  Always stores discovered admins (even empty list) in Settings so other
  components can distinguish "never discovered" from "discovered but none found".

  The `opts` argument is currently reserved for future use (e.g. overriding
  the discovery port or concurrency); pass `[]` for now.
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
        probe_all_networks(ping_data, network_name)

      {:error, reason} ->
        Logger.error("Failed to ping peers: #{inspect(reason)}")
        Settings.set_admin_urls([])
        {:ok, network_name, []}
    end
  end

  defp probe_all_networks(ping_data, fallback_network) do
    Logger.info("Inspecting peers on #{map_size(ping_data)} network(s) for admins...")

    discovery_port = Application.get_env(:edge_agent, :admin_discovery_port, 44_000)
    max_concurrency = Application.get_env(:edge_agent, :admin_discovery_concurrency, 10)

    results =
      ping_data
      |> flatten_peer_jobs()
      |> probe_peers_async(discovery_port, max_concurrency)

    admin_urls = results |> Enum.map(fn {_net, url} -> url end) |> Enum.uniq()
    found_network = first_network_or(results, fallback_network)

    record_discovery(found_network, admin_urls)
  end

  # Flatten {network, peer} pairs so probes across all networks run in one
  # parallel pass instead of network-by-network sequentially.
  defp flatten_peer_jobs(ping_data) do
    Enum.flat_map(ping_data, fn {net_name, peers} ->
      Enum.map(peers, &{net_name, &1})
    end)
  end

  defp probe_peers_async(peer_jobs, discovery_port, max_concurrency) do
    peer_jobs
    |> Task.async_stream(
      fn {net_name, peer} -> {net_name, probe_peer(peer, net_name, discovery_port)} end,
      max_concurrency: max_concurrency,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {net_name, urls}} -> Enum.map(urls, &{net_name, &1})
      {:exit, _} -> []
    end)
  end

  # First network with a successful probe; falls back to whatever we got
  # from the network list if nothing answered.
  defp first_network_or([{net, _} | _], _fallback), do: net
  defp first_network_or([], fallback), do: fallback

  defp record_discovery(found_network, []) do
    Logger.warning("No admins discovered across any network")
    Settings.set_admin_urls([])
    {:ok, found_network, []}
  end

  defp record_discovery(found_network, admin_urls) do
    Logger.info("Discovered #{length(admin_urls)} unique admin(s) across all networks")
    Settings.set_admin_urls(admin_urls)
    {:ok, found_network, admin_urls}
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
