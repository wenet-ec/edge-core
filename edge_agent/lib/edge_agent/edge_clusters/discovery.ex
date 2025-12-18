# edge_agent/lib/edge_agent/edge_clusters/discovery.ex
defmodule EdgeAgent.EdgeClusters.Discovery do
  @moduledoc """
  Admin discovery via subnet scanning.

  Scans the cluster subnet to find admins, constructs DNS hostnames
  for discovered admins based on the cluster's network context.

  This module combines cluster info retrieval and admin discovery
  into a single operation.
  """

  require Logger

  import Bitwise

  alias EdgeAgent.Settings

  @doc """
  Discover admins in the cluster.

  Scans ALL connected networks and aggregates all discovered admins.
  Only scans networks where we are actually connected (not just joined).
  This provides resilience against network glitches - if one network has issues,
  we still discover admins on other networks.

  Returns `{:ok, network_name, admin_urls}` where:
  - network_name is the full Netmaker network name (e.g., "cluster-default")
  - admin_urls is a list of HTTP URLs: ["http://admin-xyz.cluster-abc.nm.internal:44000", ...]

  Stores discovered admins in Settings table as JSON-encoded list.

  ## Options
  - `fail_on_empty` - If true, returns error when no admins found. If false, returns empty list. Defaults to false.
  """
  def discover_admins(opts \\ []) do
    fail_on_empty = Keyword.get(opts, :fail_on_empty, false)

    case Nexmaker.Cli.list_networks() do
      {:ok, networks} when is_list(networks) and networks != [] ->
        # Filter to only connected networks
        connected_networks = Enum.filter(networks, fn net -> net["connected"] == true end)

        if Enum.empty?(connected_networks) do
          {:error, "No connected networks found"}
        else
          Logger.info("Scanning #{length(connected_networks)} connected network(s) for admins...")

          # Scan all connected networks and collect all discovered admins
          results =
            Enum.map(connected_networks, fn network_info ->
              network_name = network_info["network"]
              cluster_id = String.replace_prefix(network_name, "cluster-", "")
              # Extract subnet from ipv4_addr (e.g., "100.63.0.1/24" -> "100.63.0.0/24")
              subnet = extract_subnet_from_cidr(network_info["ipv4_addr"])
              # Extract our own IP to exclude from scanning
              self_ip = extract_ip_from_cidr(network_info["ipv4_addr"])

              case scan_subnet(subnet, cluster_id, self_ip) do
                {:ok, admin_urls} -> {network_name, admin_urls}
                {:error, _reason} -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          case results do
            [{network_name, _admin_urls} | _rest] ->
              # Aggregate all discovered admins from all networks
              all_admin_urls =
                Enum.flat_map(results, fn {_network, urls} -> urls end) |> Enum.uniq()

              Logger.info(
                "Discovered total of #{length(all_admin_urls)} unique admin(s) across all networks"
              )

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

      {:ok, []} ->
        {:error, "No networks found"}

      {:error, reason} ->
        {:error, "Failed to list networks: #{inspect(reason)}"}
    end
  end

  # Extract just the IP address from CIDR (e.g., "100.64.0.2/24" -> "100.64.0.2")
  defp extract_ip_from_cidr(cidr) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [ip, _mask] -> ip
      _ -> nil
    end
  end

  defp extract_ip_from_cidr(_), do: nil

  # Extract network subnet from node's IP CIDR (e.g., "100.63.0.1/24" -> "100.63.0.0/24")
  defp extract_subnet_from_cidr(cidr) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [ip_string, netmask] ->
        case parse_ip(ip_string) do
          {:ok, ip_parts} ->
            # Parse netmask to calculate network address
            case Integer.parse(netmask) do
              {mask_bits, ""} ->
                # Convert IP to 32-bit integer
                ip_int = ip_parts |> Enum.reduce(0, fn part, acc -> acc * 256 + part end)

                # Create subnet mask and apply to get network address
                mask = bnot((:math.pow(2, 32 - mask_bits) |> trunc()) - 1)
                network_ip = band(ip_int, mask)

                # Convert back to dotted notation
                network_string =
                  [
                    band(bsr(network_ip, 24), 255),
                    band(bsr(network_ip, 16), 255),
                    band(bsr(network_ip, 8), 255),
                    band(network_ip, 255)
                  ]
                  |> Enum.join(".")

                "#{network_string}/#{mask_bits}"

              _ ->
                cidr
            end

          _ ->
            cidr
        end

      _ ->
        cidr
    end
  end

  defp extract_subnet_from_cidr(_), do: nil

  # Scan subnet for admins using nmap
  defp scan_subnet(nil, _cluster_id, _self_ip), do: {:error, "Invalid subnet"}

  defp scan_subnet(subnet, cluster_id, self_ip) when is_binary(subnet) do
    discovery_port = Application.get_env(:edge_agent, :admin_discovery_port, 44000)
    default_domain = Application.get_env(:edge_agent, :netmaker_default_domain, "nm.internal")

    Logger.info(
      "Scanning subnet #{subnet} for admins on port #{discovery_port} (excluding self: #{self_ip})..."
    )

    # Use nmap to find hosts with port open
    case scan_with_nmap(subnet, discovery_port) do
      {:ok, ips_with_port_open} ->
        # Filter out our own IP
        ips_to_query =
          if self_ip,
            do: Enum.reject(ips_with_port_open, &(&1 == self_ip)),
            else: ips_with_port_open

        Logger.info(
          "Found #{length(ips_with_port_open)} host(s) with port #{discovery_port} open"
        )

        Logger.debug("IPs to query (after excluding self): #{inspect(ips_to_query)}")

        # Now query each IP with port open to get admin info
        admin_urls =
          ips_to_query
          |> Enum.map(fn ip ->
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
                  Logger.debug("✗ #{ip} returned invalid JSON response")
                  nil
                end

              {:error, reason} ->
                Logger.debug("✗ #{ip} HTTP request failed: #{inspect(reason)}")
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        if Enum.empty?(admin_urls) do
          {:error, "No admins discovered in subnet"}
        else
          Logger.info("Discovered #{length(admin_urls)} admin(s)")
          {:ok, admin_urls}
        end

      {:error, reason} ->
        {:error, "nmap scan failed: #{inspect(reason)}"}
    end
  end

  # Use nmap to scan for hosts with specific port open
  defp scan_with_nmap(subnet, port) do
    # nmap -Pn -p <port> --open -oG - <subnet>
    # -Pn: Skip ping, directly scan ports (faster)
    # --host-timeout: Timeout per host to prevent hanging on unresponsive networks
    # Returns greppable output, we parse for "Host: <ip> ... Ports: <port>/open"

    # Wrap in Task.async with timeout to prevent infinite blocking
    task =
      Task.async(fn ->
        System.cmd(
          "nmap",
          ["-Pn", "-p", "#{port}", "--open", "--host-timeout", "2s", "-oG", "-", subnet],
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, 15_000) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        ips = parse_nmap_output(output)
        {:ok, ips}

      {:ok, {output, exit_code}} ->
        Logger.error("nmap failed with exit code #{exit_code}: #{output}")
        {:error, {:nmap_error, exit_code, output}}

      nil ->
        Logger.error("nmap scan timed out after 15 seconds")
        {:error, :scan_timeout}
    end
  rescue
    e ->
      Logger.error("nmap command failed: #{inspect(e)}")
      {:error, :nmap_not_found}
  end

  # Parse nmap greppable output for IPs with port open
  # Example line: "Host: 100.64.0.1 () Ports: 44000/open/tcp//..."
  defp parse_nmap_output(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "Host: "))
    |> Enum.map(fn line ->
      case Regex.run(~r/Host: ([0-9.]+)/, line) do
        [_, ip] -> ip
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # Build DNS hostname
  defp build_hostname(host, network, ""), do: "#{host}.#{network}"
  defp build_hostname(host, network, domain), do: "#{host}.#{network}.#{domain}"

  # Parse IP address string to list of integers
  defp parse_ip(ip_string) do
    parts =
      ip_string
      |> String.split(".")
      |> Enum.map(&parse_integer/1)

    if length(parts) == 4 and Enum.all?(parts, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parts, fn {:ok, n} -> n end)}
    else
      :error
    end
  end

  # Safe integer parsing
  defp parse_integer(string) do
    case Integer.parse(string) do
      {int, ""} when int >= 0 and int <= 255 -> {:ok, int}
      _ -> :error
    end
  end
end
