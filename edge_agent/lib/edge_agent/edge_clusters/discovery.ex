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

  alias EdgeAgent.Settings

  @doc """
  Discover admins in the cluster.

  Returns `{:ok, cluster_id, admin_urls}` where admin_urls is a list of HTTP URLs:
  ```
  ["http://admin-xyz.cluster-abc.nm.internal:44000", ...]
  ```

  Stores discovered admins in Settings table as JSON-encoded list.
  """
  def discover_admins do
    with {:ok, cluster_id, subnet} <- get_cluster_info(),
         {:ok, admin_urls} <- scan_subnet(subnet, cluster_id) do
      # Store in Settings for AdminClient to use
      Settings.set("admin_urls", Jason.encode!(admin_urls))
      {:ok, cluster_id, admin_urls}
    end
  end

  # Get cluster info from netclient
  defp get_cluster_info do
    case Netmaker.Cli.list_networks() do
      {:ok, [network_info | _]} ->
        # Extract cluster_id from network name (e.g., "cluster-abc456" → "abc456")
        cluster_id = String.replace_prefix(network_info.network, "cluster-", "")
        {:ok, cluster_id, network_info.subnet}

      {:ok, []} ->
        {:error, "No networks found"}

      {:error, reason} ->
        {:error, "Failed to list networks: #{inspect(reason)}"}
    end
  end

  # Scan subnet for admins
  defp scan_subnet(subnet, cluster_id) do
    discovery_port = Application.get_env(:edge_agent, :admin_discovery_port, 44000)
    default_domain = Application.get_env(:edge_agent, :netmaker_default_domain, "nm.internal")

    Logger.info("Scanning subnet #{subnet} for admins...")

    admin_urls =
      subnet
      |> generate_ips()
      |> Task.async_stream(
        fn ip ->
          url = "http://#{ip}:#{discovery_port}/api/admins/self/discovery"

          case Req.get(url, receive_timeout: 500, retry: false) do
            {:ok, %{status: 200, body: %{"name" => admin_name}}} ->
              # Construct DNS hostname for this cluster
              dns_hostname = build_hostname(admin_name, "cluster-#{cluster_id}", default_domain)
              admin_url = "http://#{dns_hostname}:#{discovery_port}"

              Logger.debug("Discovered admin: #{admin_name} at #{admin_url}")
              admin_url

            _ ->
              nil
          end
        end,
        max_concurrency: 50,
        timeout: 1000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(admin_urls) do
      {:error, "No admins discovered in subnet"}
    else
      Logger.info("Discovered #{length(admin_urls)} admin(s)")
      {:ok, admin_urls}
    end
  end

  # Build DNS hostname
  defp build_hostname(host, network, ""), do: "#{host}.#{network}"
  defp build_hostname(host, network, domain), do: "#{host}.#{network}.#{domain}"

  # Generate list of IPs from CIDR subnet
  defp generate_ips(subnet) do
    case parse_cidr(subnet) do
      {:ok, base_ip, netmask} ->
        # Calculate number of hosts (2^(32 - netmask) - 2, excluding network and broadcast)
        host_bits = 32 - netmask
        max_hosts = :math.pow(2, host_bits) |> trunc()

        # Generate all host IPs (skip network address at 0 and broadcast at max)
        for i <- 1..(max_hosts - 1) do
          increment_ip(base_ip, i)
        end

      :error ->
        Logger.error("Failed to parse subnet: #{subnet}")
        []
    end
  end

  # Parse CIDR notation (e.g., "10.0.0.0/24")
  defp parse_cidr(subnet) do
    case String.split(subnet, "/") do
      [ip_string, netmask_string] ->
        with {:ok, netmask} <- parse_integer(netmask_string),
             {:ok, ip_parts} <- parse_ip(ip_string) do
          # Convert IP to 32-bit integer
          base_ip =
            ip_parts
            |> Enum.reduce(0, fn part, acc -> acc * 256 + part end)

          # Mask off host bits to get network address
          mask = ~~~((:math.pow(2, 32 - netmask) |> trunc()) - 1)
          network_ip = Bitwise.band(base_ip, mask)

          {:ok, network_ip, netmask}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

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

  # Increment IP address by offset
  defp increment_ip(base_ip, offset) do
    new_ip = base_ip + offset

    # Convert back to dotted notation
    [
      Bitwise.band(Bitwise.bsr(new_ip, 24), 255),
      Bitwise.band(Bitwise.bsr(new_ip, 16), 255),
      Bitwise.band(Bitwise.bsr(new_ip, 8), 255),
      Bitwise.band(new_ip, 255)
    ]
    |> Enum.join(".")
  end
end
