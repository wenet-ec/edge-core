# edge_admin/lib/edge_admin/admins/discovery.ex
defmodule EdgeAdmin.Admins.Discovery do
  @moduledoc """
  Admin cluster discovery and VPN network management.

  Handles:
  - Creating and joining admin cluster networks
  - Querying Netmaker API for peer admin discovery
  - Erlang node connection to discovered peers
  """

  require Logger

  def scan_and_connect_admins do
    # Read admin cluster name from Application config (always available)
    network_name = Application.get_env(:edge_admin, :admin_cluster_name)

    # Query Netmaker API for all nodes in the admin network
    case Nexmaker.Api.Nodes.list(network_name) do
      {:ok, nodes} when is_list(nodes) ->
        # Extract IPs from nodes (excluding empty addresses)
        ips =
          nodes
          |> Enum.map(& &1["address"])
          |> Enum.reject(&(is_nil(&1) or &1 == ""))

        Logger.debug("Found #{length(ips)} node(s) in #{network_name}, probing for peer admins")

        # Probe only actual nodes instead of entire subnet
        discovered_peers = probe_nodes_for_admins(ips, network_name)

        # Get currently connected nodes
        connected_nodes = Node.list()

        # Connect to any new peers
        new_peers =
          discovered_peers
          |> Enum.reject(fn peer -> peer in connected_nodes end)

        if length(new_peers) > 0 do
          Logger.info("Found #{length(new_peers)} new peer admin(s) to connect")

          Enum.each(new_peers, fn peer ->
            case Node.connect(peer) do
              true ->
                Logger.info("Connected to new admin: #{peer}")

              false ->
                Logger.warning("Failed to connect to discovered admin: #{peer}")

              :ignored ->
                :ok
            end
          end)
        else
          Logger.debug("No new peer admins discovered")
        end

        :ok

      {:ok, _} ->
        Logger.debug("Unexpected response format from Netmaker API")
        :ok

      {:error, reason} ->
        Logger.debug("Could not query Netmaker API for peer discovery: #{inspect(reason)}")
        Logger.debug("Skipping peer discovery")
        :ok
    end
  end

  defp probe_nodes_for_admins(ips, network_name) do
    discovery_port = Application.get_env(:edge_admin, :admin_discovery_port, 4000)
    default_domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")

    # TCP scan + HTTP probe (parallel)
    Task.async_stream(
      ips,
      fn ip ->
        probe_admin_node(ip, discovery_port, network_name, default_domain)
      end,
      max_concurrency: 10,
      timeout: 2000,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, node_name}} -> [node_name]
      {:ok, {:error, _reason}} -> []
      {:exit, _reason} -> []
    end)
  end

  def create_and_join_admin_cluster(admin_cluster_name) do
    with :ok <- ensure_network_exists(admin_cluster_name),
         {:ok, key} <- create_enrollment_key(admin_cluster_name),
         :ok <- join_network(key) do
      :ok
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_network_exists(network_name) do
    case Nexmaker.Api.Networks.get(network_name) do
      {:ok, _network} ->
        :ok

      {:error, :not_found} ->
        create_network(network_name)

      # Netmaker returns 500 with "no result found" for non-existent networks
      {:error, {:http_error, 500, body}} ->
        if String.contains?(body, "no result found") do
          create_network(network_name)
        else
          {:error, {:http_error, 500, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_network(network_name) do
    admin_cluster_subnet = Application.get_env(:edge_admin, :admin_cluster_subnet)

    case Nexmaker.Api.Networks.create(network_name, %{addressrange: admin_cluster_subnet}) do
      {:ok, _network} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_enrollment_key(network_name) do
    admin_name = Application.get_env(:edge_admin, :admin_name)

    Nexmaker.Api.EnrollmentKeys.create(network_name, %{
      uses_remaining: 1,
      expiration: 86400,
      tags: [admin_name]
    })
  end

  defp join_network(key) do
    admin_name = Application.get_env(:edge_admin, :admin_name)

    case Nexmaker.Cli.join_network(token: key["token"], name: admin_name) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp probe_admin_node(ip, discovery_port, network_name, default_domain) do
    # TCP connect scan on configured port
    case :gen_tcp.connect(String.to_charlist(ip), discovery_port, [:binary], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

        # HTTP probe
        url = "http://#{ip}:#{discovery_port}/api/admins/self/discovery"

        case HTTPoison.get(url, [], timeout: 1000, recv_timeout: 1000) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"name" => admin_name}} ->
                # Construct DNS hostname: admin_name.network_name.domain
                dns_hostname = build_hostname(admin_name, network_name, default_domain)
                erlang_node_name = :"admin@#{dns_hostname}"
                {:ok, erlang_node_name}

              _ ->
                {:error, :invalid_response}
            end

          _ ->
            {:error, :http_failed}
        end

      {:error, _reason} ->
        {:error, :tcp_failed}
    end
  end

  defp build_hostname(host, network, ""), do: "#{host}.#{network}"
  defp build_hostname(host, network, domain), do: "#{host}.#{network}.#{domain}"
end
