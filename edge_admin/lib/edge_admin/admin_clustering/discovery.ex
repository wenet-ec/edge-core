# edge_admin/lib/edge_admin/admin_clustering/discovery.ex
defmodule EdgeAdmin.AdminClustering.Discovery do
  @moduledoc """
  Peer admin discovery and Erlang node connection.

  Peers are discovered from the admin cluster VPN network rather than static
  host lists. Online peer hostnames are converted to Erlang node names and
  connected with `Node.connect/1`.

  ## Discovery Process

  ```
  1. Query Edge VPN for all nodes in admin cluster network
  2. Filter to online/connected nodes only
  3. Query Edge VPN for hosts corresponding to those nodes
  4. Extract hostnames from hosts
  5. Exclude self from list
  6. Build Erlang node names from hostnames
  7. Attempt connection to each peer
  ```

  ## DNS Retry Logic

  VPN DNS may lag immediately after a peer joins. Discovery retries name
  resolution briefly, then lets the next scheduled scan try again.

  ## Connection States

  - `true` - New connection established successfully
  - `false` - Connection failed (DNS ok, node unreachable)
  - `:ignored` - Already connected to this node

  ## Examples

      # Called during membership startup and on the discovery cron
      iex> Discovery.scan_and_connect_admins()
      :ok

      iex> Node.list()
      [:"admin@admin-def456.admin-cluster-a.nm.internal"]
  """

  alias EdgeAdmin.Vpn

  require Logger

  @doc "Discovers peer Admins through the Admin VPN and attempts Erlang connections."
  @spec scan_and_connect_admins() :: :ok
  def scan_and_connect_admins do
    network_name = Vpn.admin_cluster_name()

    with {:ok, nodes} when is_list(nodes) <- Vpn.list_nodes(network_name),
         {:ok, hosts} when is_list(hosts) <- Vpn.list_hosts() do
      do_connect_peers(nodes, hosts, network_name)
    else
      {:error, reason} ->
        Logger.debug("Could not query Edge VPN API for peer discovery: #{inspect(reason)}")
        Logger.debug("Skipping peer discovery")
        :ok

      _ ->
        Logger.debug("Unexpected response format from Edge VPN API")
        :ok
    end
  end

  defp do_connect_peers(nodes, hosts, network_name) do
    self_hostname = Application.get_env(:edge_admin, :admin_name)

    online_node_host_ids =
      nodes
      |> Enum.filter(&(&1["connected"] == true and &1["status"] == "online"))
      |> MapSet.new(& &1["hostid"])

    peer_hostnames =
      hosts
      |> Enum.filter(&MapSet.member?(online_node_host_ids, &1["id"]))
      |> Enum.map(& &1["name"])
      |> Enum.reject(&(is_nil(&1) or &1 == "" or &1 == self_hostname))

    Logger.debug("Found #{length(peer_hostnames)} online peer admin(s) in #{network_name}")

    peer_nodes =
      peer_hostnames
      |> Enum.map(&Vpn.build_vpn_hostname(&1, network_name))
      |> Enum.map(&Vpn.build_admin_erlang_node_name/1)

    connected_nodes = Node.list()
    new_peers = Enum.reject(peer_nodes, fn peer -> peer in connected_nodes end)

    if length(new_peers) > 0 do
      Logger.info("Found #{length(new_peers)} new peer admin(s) to connect")
      Enum.each(new_peers, &connect_to_peer/1)
    else
      Logger.debug("No new peer admins discovered")
    end

    :telemetry.execute(
      [:edge_admin, :discovery, :scan_complete],
      %{connected_peers: length(connected_nodes)},
      %{}
    )

    :ok
  end

  defp connect_to_peer(peer) do
    peer_hostname = peer |> Atom.to_string() |> String.split("@") |> List.last()
    Logger.info("Connecting to peer: #{peer_hostname}")

    case wait_for_dns_resolution(peer_hostname, 3, 2000) do
      {:ok, _hostent} ->
        emit_dns_telemetry(:success)
        handle_node_connect(peer, peer_hostname)

      {:error, :nxdomain} ->
        Logger.warning("DNS not ready for #{peer_hostname} (will retry in next discovery cycle)")
        emit_dns_telemetry(:nxdomain)

      {:error, _reason} ->
        Logger.warning("DNS error for #{peer_hostname}")
        emit_dns_telemetry(:error)
    end
  end

  defp handle_node_connect(peer, peer_hostname) do
    case Node.connect(peer) do
      true ->
        Logger.info("✓ Connected to admin: #{peer_hostname}")
        Logger.debug("Total connected nodes: #{length(Node.list())}")
        emit_peer_connection_telemetry(:success)

      false ->
        Logger.warning("✗ Connection failed to #{peer_hostname} (DNS ok, node unreachable)")
        emit_peer_connection_telemetry(:failure)

      :ignored ->
        Logger.debug("Already connected to #{peer_hostname}")
        emit_peer_connection_telemetry(:already_connected)
    end
  end

  defp emit_dns_telemetry(result) do
    :telemetry.execute(
      [:edge_admin, :discovery, :dns_resolution],
      %{count: 1, total: 1},
      %{result: result}
    )
  end

  defp emit_peer_connection_telemetry(result) do
    :telemetry.execute(
      [:edge_admin, :discovery, :peer_connection],
      %{count: 1, total: 1},
      %{result: result}
    )
  end

  # VPN DNS can lag just after a peer joins; a failed scan is retried by the
  # next discovery cycle.
  defp wait_for_dns_resolution(hostname, max_attempts, delay_ms) do
    Enum.reduce_while(1..max_attempts, {:error, :nxdomain}, fn attempt, _acc ->
      case :inet.gethostbyname(String.to_charlist(hostname)) do
        {:ok, hostent} ->
          if attempt > 1 do
            Logger.debug("DNS resolved for #{hostname} after #{attempt} attempts")
          end

          {:halt, {:ok, hostent}}

        {:error, :nxdomain} when attempt < max_attempts ->
          Process.sleep(delay_ms)
          {:cont, {:error, :nxdomain}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
