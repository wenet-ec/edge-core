# edge_admin/lib/edge_admin/admins/discovery.ex
defmodule EdgeAdmin.Admins.Discovery do
  @moduledoc """
  Admin cluster peer discovery.

  Handles:
  - Querying Netmaker API for peer admin discovery
  - Erlang node connection to discovered peers
  """

  alias EdgeAdmin.Vpn

  require Logger

  def scan_and_connect_admins do
    # Read admin cluster name from Application config (always available)
    network_name = Vpn.admin_cluster_name()

    # Query Netmaker API for all hosts and nodes in the admin network
    with {:ok, nodes} when is_list(nodes) <- Vpn.list_nodes(network_name),
         {:ok, hosts} when is_list(hosts) <- Vpn.list_hosts() do
      # Get current admin's hostname to exclude self
      self_hostname = Application.get_env(:edge_admin, :admin_name)

      # Extract host IDs from nodes in this network
      node_host_ids = nodes |> Enum.map(& &1["hostid"]) |> MapSet.new()

      # Filter hosts that are in this network, extract hostnames, exclude self
      peer_hostnames =
        hosts
        |> Enum.filter(&MapSet.member?(node_host_ids, &1["id"]))
        |> Enum.map(& &1["name"])
        |> Enum.reject(&(is_nil(&1) or &1 == "" or &1 == self_hostname))

      Logger.debug("Found #{length(peer_hostnames)} peer admin(s) in #{network_name}")

      # Build Erlang node names from hostnames
      peer_nodes =
        peer_hostnames
        |> Enum.map(fn hostname ->
          dns_hostname = Vpn.build_hostname(hostname, network_name)
          :"admin@#{dns_hostname}"
        end)

      # Get currently connected nodes
      connected_nodes = Node.list()

      # Connect to any new peers
      new_peers =
        peer_nodes
        |> Enum.reject(fn peer -> peer in connected_nodes end)

      if length(new_peers) > 0 do
        Logger.info("Found #{length(new_peers)} new peer admin(s) to connect")

        Enum.each(new_peers, fn peer ->
          peer_hostname = peer |> Atom.to_string() |> String.split("@") |> List.last()
          Logger.info("Connecting to peer: #{peer_hostname}")

          # Wait for DNS to propagate (up to 3 attempts with 2s delay)
          # This handles the timing issue where netclient just joined the VPN
          dns_result = wait_for_dns_resolution(peer_hostname, 3, 2000)

          case dns_result do
            {:ok, _hostent} ->
              # DNS resolved, attempt connection
              case Node.connect(peer) do
                true ->
                  Logger.info("✓ Connected to admin: #{peer_hostname}")
                  Logger.debug("Total connected nodes: #{length(Node.list())}")

                false ->
                  Logger.warning("✗ Connection failed to #{peer_hostname} (DNS ok, node unreachable)")

                :ignored ->
                  Logger.debug("Already connected to #{peer_hostname}")
              end

            {:error, :nxdomain} ->
              Logger.warning(
                "DNS not ready for #{peer_hostname} (will retry in next discovery cycle)"
              )

            {:error, reason} ->
              Logger.warning("DNS error for #{peer_hostname}: #{inspect(reason)}")
          end
        end)
      else
        Logger.debug("No new peer admins discovered")
      end

      :ok
    else
      {:error, reason} ->
        Logger.debug("Could not query Netmaker API for peer discovery: #{inspect(reason)}")
        Logger.debug("Skipping peer discovery")
        :ok

      _ ->
        Logger.debug("Unexpected response format from Netmaker API")
        :ok
    end
  end

  # Wait for DNS resolution with retry logic
  # This handles timing issues when a peer just joined the VPN and DNS hasn't propagated yet
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
