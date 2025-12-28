# edge_agent/lib/edge_agent/edge_clusters/discovery.ex
defmodule EdgeAgent.EdgeClusters.Discovery do
  @moduledoc """
  Admin server discovery via WireGuard peer inspection.

  This module discovers admin servers on the VPN network by inspecting WireGuard peers
  and querying their discovery endpoints. This is more efficient than subnet scanning
  since we directly query WireGuard for connected peers instead of scanning entire CIDR blocks.

  ## Key Concepts

  - **Peer Discovery**: Query WireGuard for list of connected peers via `netclient peers`
  - **Admin Identification**: HTTP GET to each peer's `/api/admins/self/discovery` endpoint
  - **DNS Resolution**: Build DNS hostnames from admin names for stable addressing
  - **Multi-Network**: Scan all connected networks and aggregate discovered admins
  - **Settings Storage**: Store discovered admin URLs in Settings table for AdminClient

  ## Discovery Process

  ```
  1. Query WireGuard for peer list (netclient peers)
  2. For each network's peers:
     a. Extract peer VPN IP and hostname
     b. Query HTTP://ip:44000/api/admins/self/discovery
     c. Extract admin name from JSON response
     d. Build DNS hostname (e.g., admin-abc123.cluster-xyz.nm.internal)
  3. Aggregate all discovered admins across all networks
  4. Store admin URLs in Settings table
  ```

  ## Discovery Modes

  - **Bootstrap Mode** (`fail_on_empty: true`) - Fail fast if no admins found (used during startup)
  - **Periodic Mode** (`fail_on_empty: false`) - Log warning but don't fail (used in periodic worker)

  ## Admin Discovery Endpoint

  Admins expose a discovery endpoint at `/api/admins/self/discovery` that returns:
  ```json
  {"name": "admin-abc123"}
  ```

  This allows agents to discover admins without hardcoded addresses.

  ## Examples

      # Bootstrap mode - fail if no admins found
      iex> Discovery.discover_admins(fail_on_empty: true)
      {:ok, "cluster-default", ["http://admin-abc.cluster-default.nm.internal:44000"]}

      # Periodic mode - log warning but don't fail
      iex> Discovery.discover_admins(fail_on_empty: false)
      {:ok, nil, []}

      # Multi-network discovery
      iex> Discovery.discover_admins()
      {:ok, "cluster-prod", [
        "http://admin-abc.cluster-prod.nm.internal:44000",
        "http://admin-def.cluster-dev.nm.internal:44000"
      ]}
  """

  alias EdgeAgent.Settings

  require Logger

  @doc """
  Discover admins in the cluster.

  Uses WireGuard peer information to discover admins on connected networks.
  This is more efficient than subnet scanning since we directly query
  WireGuard for the list of connected peers.

  Returns `{:ok, network_name, admin_urls}` where:
  - network_name is the full Netmaker network name (e.g., "cluster-default")
  - admin_urls is a list of HTTP URLs: ["http://admin-xyz.cluster-abc.nm.internal:44000", ...]

  Stores discovered admins in Settings table as JSON-encoded list.

  ## Options
  - `fail_on_empty` - If true, returns error when no admins found. If false, returns empty list. Defaults to false.
  """
  @spec discover_admins(keyword()) ::
          {:ok, String.t() | nil, [String.t()]} | {:error, String.t()}
  def discover_admins(opts \\ []) do
    fail_on_empty = Keyword.get(opts, :fail_on_empty, false)

    case Nexmaker.Cli.list_peers() do
      {:ok, peer_data} when is_map(peer_data) ->
        peers_by_network = Map.get(peer_data, "peers", %{})

        if map_size(peers_by_network) == 0 do
          if fail_on_empty do
            {:error, "No peers found on any network"}
          else
            Logger.warning("No peers found on any network")
            {:ok, nil, []}
          end
        else
          Logger.info("Inspecting peers on #{map_size(peers_by_network)} network(s) for admins...")

          # Scan all networks and collect all discovered admins
          results =
            peers_by_network
            |> Enum.map(fn {network_name, peers} ->
              cluster_id = String.replace_prefix(network_name, "cluster-", "")

              case discover_admins_from_peers(peers, cluster_id, network_name) do
                {:ok, admin_urls} -> {network_name, admin_urls}
                {:error, _reason} -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          case results do
            [{network_name, _admin_urls} | _rest] ->
              # Aggregate all discovered admins from all networks
              all_admin_urls =
                results |> Enum.flat_map(fn {_network, urls} -> urls end) |> Enum.uniq()

              Logger.info("Discovered total of #{length(all_admin_urls)} unique admin(s) across all networks")

              # Store in Settings for AdminClient to use
              Settings.set_admin_urls(all_admin_urls)
              {:ok, network_name, all_admin_urls}

            [] ->
              if fail_on_empty do
                {:error, "No admins discovered across any network"}
              else
                Logger.warning("No admins discovered across any network")
                {:ok, nil, []}
              end
          end
        end

      {:error, reason} ->
        {:error, "Failed to list peers: #{inspect(reason)}"}
    end
  end

  # Discover admins from peer list
  defp discover_admins_from_peers(peers, cluster_id, network_name) when is_list(peers) do
    discovery_port = Application.get_env(:edge_agent, :admin_discovery_port, 44_000)
    default_domain = Application.get_env(:edge_agent, :netmaker_default_domain, "nm.internal")

    Logger.info("Checking #{length(peers)} peer(s) on network #{network_name} for admins...")

    # Query each peer's allowed IPs to find admin nodes
    admin_urls =
      peers
      |> Enum.map(fn peer ->
        # Get the first allowed IP (usually the VPN IP)
        ip =
          case peer["allowed_ips"] do
            [first_ip | _rest] ->
              # Strip CIDR notation if present (e.g., "100.64.0.1/32" -> "100.64.0.1")
              first_ip |> String.split("/") |> List.first()

            _ ->
              nil
          end

        hostname = peer["host_name"]

        if ip && hostname do
          # Try to query the peer's discovery endpoint
          url = "http://#{ip}:#{discovery_port}/api/admins/self/discovery"

          case Req.get(url, receive_timeout: 5000, retry: false) do
            {:ok, %{status: 200, body: body}} ->
              admin_name =
                cond do
                  is_map(body) and Map.has_key?(body, "name") ->
                    body["name"]

                  is_binary(body) ->
                    case Jason.decode(body) do
                      {:ok, %{"name" => name}} -> name
                      _ -> nil
                    end

                  true ->
                    nil
                end

              if admin_name do
                # Construct DNS hostname for this cluster
                dns_hostname =
                  build_hostname(admin_name, "cluster-#{cluster_id}", default_domain)

                admin_url = "http://#{dns_hostname}:#{discovery_port}"

                Logger.info("✓ Discovered admin: #{admin_name} at #{admin_url}")
                admin_url
              else
                Logger.debug("✗ #{ip} (#{hostname}) returned invalid JSON response")
                nil
              end

            {:error, reason} ->
              Logger.debug("✗ #{ip} (#{hostname}) HTTP request failed: #{inspect(reason)}")
              nil
          end
        else
          Logger.debug("✗ Peer has no usable IP or hostname: #{inspect(peer)}")
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(admin_urls) do
      {:error, "No admins discovered from peers on network #{network_name}"}
    else
      Logger.info("Discovered #{length(admin_urls)} admin(s) on network #{network_name}")
      {:ok, admin_urls}
    end
  end

  # Build DNS hostname
  defp build_hostname(host, network, ""), do: "#{host}.#{network}"
  defp build_hostname(host, network, domain), do: "#{host}.#{network}.#{domain}"
end
