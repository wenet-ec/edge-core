# edge_agent/lib/edge_agent/ingress_tunneling/forwarding.ex
defmodule EdgeAgent.IngressTunneling.Forwarding do
  @moduledoc "Installs the Ingress firewall policy that limits clients to the selected Edge VPN cluster."

  alias EdgeAgent.IngressTunneling.SystemCommand

  @interface "edge_ingress"
  @vpn_interface "netmaker"
  @forward_chain "EDGE_INGRESS_FWD"
  @nat_chain "EDGE_INGRESS_NAT"
  @input_chain "EDGE_INGRESS_IN"

  @doc "Installs scoped forwarding rules and refuses to proceed unless cluster routes use Edge VPN."
  @spec install(map()) :: :ok | {:error, term()}
  def install(config) do
    with :ok <- require_forwarding("/proc/sys/net/ipv4/ip_forward"),
         :ok <- require_forwarding("/proc/sys/net/ipv6/conf/all/forwarding"),
         :ok <- require_vpn_interface(),
         :ok <- install_family(:iptables, config["vpn_ipv4_range"], tunnel_addresses(config, :ipv4)) do
      install_family(:ip6tables, config["vpn_ipv6_range"], tunnel_addresses(config, :ipv6))
    end
  end

  @spec remove() :: :ok
  def remove do
    remove_family(:iptables)
    remove_family(:ip6tables)

    Enum.each([:iptables, :ip6tables], fn iptables ->
      delete_jump(iptables, "INPUT", @input_chain)
      delete_chain(iptables, @input_chain)
    end)

    :ok
  end

  @spec block_listener(pos_integer()) :: :ok | {:error, term()}
  def block_listener(listen_port) do
    with :ok <- install_input_rule(:iptables, listen_port) do
      install_input_rule(:ip6tables, listen_port)
    end
  end

  defp install_family(iptables, vpn_range, tunnel_addresses) do
    with :ok <- create_chain(iptables, "FORWARD", @forward_chain),
         :ok <- create_chain(iptables, "POSTROUTING", @nat_chain, ["-t", "nat"]),
         :ok <-
           rule(iptables, [
             "-A",
             @forward_chain,
             "-i",
             @interface,
             "-o",
             @vpn_interface,
             "-d",
             vpn_range,
             "-j",
             "ACCEPT"
           ]),
         :ok <-
           rule(iptables, [
             "-A",
             @forward_chain,
             "-i",
             @vpn_interface,
             "-o",
             @interface,
             "-s",
             vpn_range,
             "-m",
             "conntrack",
             "--ctstate",
             "RELATED,ESTABLISHED",
             "-j",
             "ACCEPT"
           ]),
         :ok <- rule(iptables, ["-A", @forward_chain, "-i", @interface, "-j", "DROP"]),
         :ok <- rule(iptables, ["-A", @forward_chain, "-o", @interface, "-j", "DROP"]) do
      add_nat_rules(iptables, vpn_range, tunnel_addresses)
    end
  end

  defp create_chain(iptables, parent, chain, extra_args \\ []) do
    case_result =
      case SystemCommand.run(iptables, extra_args ++ ["-N", chain]) do
        {:ok, _} ->
          :ok

        {:error, _} ->
          case SystemCommand.run(iptables, extra_args ++ ["-S", chain]) do
            {:ok, _} -> iptables |> SystemCommand.run(extra_args ++ ["-F", chain]) |> command_result()
            {:error, reason} -> {:error, {:firewall_chain_create_failed, chain, reason}}
          end
      end

    case case_result do
      :ok -> ensure_jump(iptables, parent, chain, extra_args)
      error -> error
    end
  end

  defp ensure_jump(iptables, parent, chain, extra_args) do
    jump = extra_args ++ ["-C", parent, "-j", chain]

    case SystemCommand.run(iptables, jump) do
      {:ok, _} -> :ok
      {:error, _} -> rule(iptables, extra_args ++ ["-I", parent, "1", "-j", chain])
    end
  end

  defp add_nat_rules(iptables, vpn_range, tunnel_addresses) do
    Enum.reduce_while(tunnel_addresses, :ok, fn address, :ok ->
      args = ["-t", "nat", "-A", @nat_chain, "-s", address, "-d", vpn_range, "-o", @vpn_interface, "-j", "MASQUERADE"]

      case rule(iptables, args) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp install_input_rule(iptables, port) do
    with :ok <- create_chain(iptables, "INPUT", @input_chain),
         :ok <-
           rule(iptables, [
             "-A",
             @input_chain,
             "-i",
             "lo",
             "-p",
             "udp",
             "--dport",
             Integer.to_string(port),
             "-j",
             "ACCEPT"
           ]),
         :ok <- rule(iptables, ["-A", @input_chain, "-i", @interface, "-p", "udp", "--dport", "53", "-j", "ACCEPT"]),
         :ok <- rule(iptables, ["-A", @input_chain, "-i", @interface, "-p", "tcp", "--dport", "53", "-j", "ACCEPT"]),
         :ok <- rule(iptables, ["-A", @input_chain, "-i", @interface, "-j", "DROP"]) do
      rule(iptables, ["-A", @input_chain, "-p", "udp", "--dport", Integer.to_string(port), "-j", "DROP"])
    end
  end

  defp require_forwarding(path) do
    case File.read(path) do
      {:ok, "1\n"} -> :ok
      {:ok, "1"} -> :ok
      {:ok, value} -> {:error, {:forwarding_disabled, path, String.trim(value)}}
      {:error, reason} -> {:error, {:forwarding_unavailable, path, reason}}
    end
  end

  defp require_vpn_interface do
    with {:ok, ipv4} <- SystemCommand.run(:ip, ["-4", "-o", "address", "show", "dev", @vpn_interface]),
         true <- String.contains?(ipv4, " inet "),
         {:ok, ipv6} <- SystemCommand.run(:ip, ["-6", "-o", "address", "show", "dev", @vpn_interface]),
         true <- String.contains?(ipv6, " inet6 ") do
      :ok
    else
      false -> {:error, :edge_vpn_interface_missing_address_family}
      {:error, reason} -> {:error, {:edge_vpn_interface_unavailable, reason}}
    end
  end

  defp tunnel_addresses(config, :ipv4), do: Enum.map(config["peers"], & &1["tunnel_ipv4_address"])
  defp tunnel_addresses(config, :ipv6), do: Enum.map(config["peers"], & &1["tunnel_ipv6_address"])

  defp remove_family(iptables) do
    delete_jump(iptables, "FORWARD", @forward_chain)
    delete_chain(iptables, @forward_chain)
    delete_jump(iptables, "POSTROUTING", @nat_chain, ["-t", "nat"])
    delete_chain(iptables, @nat_chain, ["-t", "nat"])
  end

  defp delete_jump(iptables, parent, chain, extra_args \\ []) do
    args = extra_args ++ ["-D", parent, "-j", chain]

    case SystemCommand.run(iptables, args) do
      {:ok, _} -> delete_jump(iptables, parent, chain, extra_args)
      {:error, _} -> :ok
    end
  end

  defp delete_chain(iptables, chain, extra_args \\ []) do
    _ = SystemCommand.run(iptables, extra_args ++ ["-F", chain])
    _ = SystemCommand.run(iptables, extra_args ++ ["-X", chain])
    :ok
  end

  defp rule(iptables, args) do
    case SystemCommand.run(iptables, args) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:firewall_rule_failed, iptables, args, reason}}
    end
  end

  defp command_result({:ok, _}), do: :ok
  defp command_result({:error, reason}), do: {:error, reason}
end
