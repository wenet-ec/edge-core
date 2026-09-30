# edge_admin/lib/edge_admin/vpn/networks.ex
defmodule EdgeAdmin.Vpn.Networks do
  @moduledoc "Edge VPN network and network-membership operations."

  alias EdgeAdmin.Vpn.Addressing
  alias EdgeAdmin.Vpn.Api, as: VpnApi
  alias EdgeAdmin.Vpn.Hosts
  alias EdgeAdmin.Vpn.Naming
  alias Nexmaker.Api, as: Api
  alias Nexmaker.Api.EnrollmentKeys
  alias Nexmaker.Api.Hosts, as: NexmakerHosts
  alias Nexmaker.Api.Networks, as: NexmakerNetworks
  alias Nexmaker.Api.Nodes, as: NexmakerNodes

  @spec list_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_networks, do: VpnApi.normalize_error(NexmakerNetworks.list())

  @spec list_network_ranges() ::
          {:ok, %{ipv4: [String.t()], ipv6: [String.t()]}} | {:error, :service_unavailable}
  def list_network_ranges do
    with {:ok, networks} <- list_networks() do
      {:ok,
       %{
         ipv4: networks |> Enum.map(& &1["addressrange"]) |> Enum.filter(&is_binary/1),
         ipv6: networks |> Enum.map(& &1["addressrange6"]) |> Enum.filter(&is_binary/1)
       }}
    end
  end

  @spec check_network_ranges(String.t(), map(), [map()]) :: :ok | {:error, {:conflict, String.t()}}
  def check_network_ranges(network_name, opts, networks) do
    ipv4_range = opts[:addressrange]
    ipv6_range = opts[:addressrange6]

    Enum.find_value(networks, :ok, fn network ->
      if network["netid"] == network_name do
        nil
      else
        cond do
          is_binary(ipv4_range) and
              Addressing.ipv4_cidrs_overlap?(ipv4_range, Enum.filter([network["addressrange"]], &is_binary/1)) ->
            {:error,
             {:conflict,
              "IPv4 range #{ipv4_range} overlaps Edge VPN network #{network["netid"]} (#{network["addressrange"]})"}}

          is_binary(ipv6_range) and
              Addressing.ipv6_cidrs_overlap?(ipv6_range, Enum.filter([network["addressrange6"]], &is_binary/1)) ->
            {:error,
             {:conflict,
              "IPv6 range #{ipv6_range} overlaps Edge VPN network #{network["netid"]} (#{network["addressrange6"]})"}}

          true ->
            nil
        end
      end
    end)
  end

  @spec list_admin_cluster_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_admin_cluster_networks do
    with {:ok, networks} <- list_networks(),
         {:ok, hosts} <- Hosts.list_hosts() do
      hosts_by_id = Map.new(hosts, fn host -> {host["id"], host} end)

      admin_networks =
        networks
        |> Enum.filter(&admin_cluster_network?/1)
        |> Enum.sort_by(& &1["netid"])

      result =
        Enum.reduce_while(admin_networks, [], fn network, acc ->
          case list_nodes(network["netid"]) do
            {:ok, nodes} ->
              members =
                nodes
                |> Enum.map(fn node -> %{node: node, host: Map.get(hosts_by_id, node["hostid"])} end)
                |> Enum.reject(fn %{host: host} -> is_nil(host) end)

              {:cont, [%{network: network, members: members} | acc]}

            {:error, _} = error ->
              {:halt, error}
          end
        end)

      case result do
        {:error, _} = error -> error
        list when is_list(list) -> {:ok, Enum.reverse(list)}
      end
    end
  end

  defp admin_cluster_network?(%{"netid" => netid}) when is_binary(netid),
    do: String.starts_with?(netid, "admin-cluster-")

  defp admin_cluster_network?(_), do: false

  @spec create_network(String.t(), map()) ::
          {:ok, map()}
          | {:error, :already_exists | :service_unavailable | String.t() | {:conflict, String.t()}}
  def create_network(network_name, opts \\ %{}) do
    with :ok <- Naming.validate_network_name(network_name) do
      case network_name |> NexmakerNetworks.create(opts) |> Api.normalize() do
        {:ok, _} = ok -> ok
        {:error, {:bad_request, body}} -> classify_create_network_400(body)
        {:error, :conflict} -> {:error, :already_exists}
        {:error, _} -> {:error, :service_unavailable}
      end
    end
  end

  @spec classify_create_network_400(term()) ::
          {:error, :already_exists | :service_unavailable | {:conflict, String.t()}}
  def classify_create_network_400(body) do
    message = Api.extract_message(body)

    cond do
      String.contains?(message, "network cidr already in use") ->
        {:error, {:conflict, "network CIDR overlaps an existing Edge VPN network"}}

      String.contains?(message, "invalid network name") ->
        {:error, :already_exists}

      true ->
        {:error, :service_unavailable}
    end
  end

  @spec delete_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_network(network_name), do: network_name |> NexmakerNetworks.delete() |> VpnApi.normalize_error()

  @spec get_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_network(network_name), do: network_name |> NexmakerNetworks.get() |> VpnApi.normalize_error()

  @spec ensure_network_exists(String.t(), map()) ::
          :ok | {:error, String.t() | :service_unavailable | {:conflict, String.t()}}
  def ensure_network_exists(network_name, create_opts \\ %{}) do
    case get_network(network_name) do
      {:ok, network} ->
        ensure_network_ranges_match(network_name, network, create_opts)

      {:error, :not_found} ->
        with :ok <- ensure_network_ranges_available(network_name, create_opts) do
          case create_network(network_name, create_opts) do
            {:ok, _} -> :ok
            {:error, :already_exists} -> resolve_network_create_race(network_name, create_opts)
            error -> error
          end
        end

      error ->
        error
    end
  end

  defp ensure_network_ranges_available(network_name, create_opts) do
    with {:ok, networks} <- list_networks(), do: check_network_ranges(network_name, create_opts, networks)
  end

  defp resolve_network_create_race(network_name, create_opts) do
    case get_network(network_name) do
      {:ok, network} ->
        ensure_network_ranges_match(network_name, network, create_opts)

      {:error, :not_found} ->
        {:error, {:conflict, "Edge VPN rejected the network CIDR because it is already in use"}}

      error ->
        error
    end
  end

  defp ensure_network_ranges_match(network_name, network, opts) do
    expected_ipv4 = opts[:addressrange]
    expected_ipv6 = opts[:addressrange6]

    if (is_nil(expected_ipv4) or network["addressrange"] == expected_ipv4) and
         (is_nil(expected_ipv6) or network["addressrange6"] == expected_ipv6) do
      :ok
    else
      {:error,
       {:conflict,
        "Edge VPN network #{network_name} has different immutable address ranges; " <>
          "recreate it before enabling dual-stack"}}
    end
  end

  @spec network_has_capacity(String.t()) ::
          :ok
          | {:error, {:network_full, %{used: non_neg_integer(), capacity: non_neg_integer(), network: String.t()}}}
          | {:error, :not_found | :service_unavailable}
  def network_has_capacity(network_name) do
    with {:ok, network} <- get_network(network_name),
         cidr when is_binary(cidr) <- network["addressrange"],
         {:ok, {_ip, prefix}} <- Addressing.parse_cidr(cidr),
         {:ok, nodes} <- list_nodes(network_name) do
      capacity = Addressing.usable_ipv4_capacity(prefix)
      used = length(nodes)

      if used >= capacity do
        {:error, {:network_full, %{used: used, capacity: capacity, network: network_name}}}
      else
        :ok
      end
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      _ -> {:error, :service_unavailable}
    end
  end

  @spec list_nodes(String.t()) :: {:ok, [map()]} | {:error, :not_found | :service_unavailable}
  def list_nodes(network_name), do: network_name |> NexmakerNodes.list() |> VpnApi.normalize_error()

  @spec remove_host_from_network(String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  def remove_host_from_network(host_id, network_name),
    do: host_id |> NexmakerHosts.remove_from_network(network_name) |> VpnApi.normalize_error()

  @spec add_host_to_network(String.t(), String.t()) ::
          {:ok, map()} | {:ok, :already_joined} | {:error, :not_found | :service_unavailable}
  def add_host_to_network(host_id, network_name) do
    case host_id |> NexmakerHosts.add_to_network(network_name) |> Api.normalize() do
      {:ok, _} = ok -> ok
      {:error, :already_exists} -> {:ok, :already_joined}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  @spec delete_node(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_node(network_name, node_id) do
    case network_name |> NexmakerNodes.delete(node_id) |> Api.normalize() do
      {:error, {:bad_request, body}} -> classify_delete_node_400(body)
      result -> VpnApi.normalize_error(result)
    end
  end

  @spec classify_delete_node_400(term()) :: {:error, :not_found | :service_unavailable}
  def classify_delete_node_400(body) do
    message = Api.extract_message(body)

    if String.contains?(message, "error fetching node during parameter validation: record not found") do
      {:error, :not_found}
    else
      {:error, :service_unavailable}
    end
  end

  @spec get_default_enrollment_key(String.t()) :: {:ok, String.t()} | {:error, :default_key_not_found}
  def get_default_enrollment_key(network_name) do
    case network_name |> EnrollmentKeys.get_default_for_network() |> Api.normalize() do
      {:ok, %{"token" => token}} when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :default_key_not_found}
    end
  end

  @spec find_node_by_host(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def find_node_by_host(network_name, host_id) do
    case list_nodes(network_name) do
      {:ok, nodes} ->
        case Enum.find(nodes, fn node -> node["hostid"] == host_id end) do
          nil -> {:error, :not_found}
          node -> {:ok, node}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
