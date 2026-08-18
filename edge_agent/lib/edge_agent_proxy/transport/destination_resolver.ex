# edge_agent/lib/edge_agent_proxy/transport/destination_resolver.ex
defmodule EdgeAgentProxy.Transport.DestinationResolver do
  @moduledoc """
  Resolves proxy destinations once and validates every returned address.

  The policy predicates live in `DestinationValidator`; this module owns DNS
  resolution and the DNS-rebinding-safe selection of the address to connect.
  """

  alias EdgeAgentProxy.Transport.DestinationValidator

  require Logger

  @typep ip_tuple :: :inet.ip4_address() | :inet.ip6_address()

  @doc """
  Resolves a host, validates every A and AAAA result, and returns one exact IP
  tuple that is safe for the caller to connect to.
  """
  @spec resolve_and_validate(String.t(), :inet.port_number()) ::
          {:ok, ip_tuple()} | {:error, atom()}
  def resolve_and_validate(host, port) when is_binary(host) and is_integer(port) do
    cond do
      DestinationValidator.custom_allowed?(host, port) ->
        case resolve_any(host) do
          {:ok, [ip | _]} ->
            Logger.debug("Proxy destination allowed (custom allowlist): #{host}:#{port}")
            {:ok, ip}

          {:error, _} ->
            Logger.warning("Proxy destination DNS resolution failed: #{host}:#{port}")
            {:error, :dns_resolution_failed}
        end

      reason = pre_dns_block_reason(host, port) ->
        Logger.warning("Proxy destination BLOCKED (#{reason}): #{host}:#{port}")
        {:error, reason}

      true ->
        case resolve_any(host) do
          {:ok, ips} ->
            check_all_ips(ips, host, port)

          {:error, _} ->
            Logger.warning("Proxy destination DNS resolution failed: #{host}:#{port}")
            {:error, :dns_resolution_failed}
        end
    end
  end

  defp pre_dns_block_reason(host, port) do
    cond do
      DestinationValidator.docker_port?(port) -> :docker_port_blocked
      DestinationValidator.kubernetes_port?(port) -> :kubernetes_port_blocked
      DestinationValidator.metrics_port?(port) -> :metrics_port_blocked
      DestinationValidator.localhost?(host) -> :localhost_blocked
      DestinationValidator.metadata_service?(host) -> :metadata_service_blocked
      DestinationValidator.link_local?(host) -> :link_local_blocked
      DestinationValidator.custom_blocked?(host, port) -> :custom_blocked
      true -> nil
    end
  end

  defp resolve_any(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, ip} ->
        {:ok, [normalise_mapped(ip)]}

      {:error, _} ->
        v4 = resolve_family(charlist, :inet)
        v6 = resolve_family(charlist, :inet6)

        case Enum.uniq(v4 ++ v6) do
          [] -> {:error, :nxdomain}
          ips -> {:ok, Enum.map(ips, &normalise_mapped/1)}
        end
    end
  end

  defp resolve_family(charlist, family) do
    case :inet.getaddrs(charlist, family) do
      {:ok, ips} -> ips
      {:error, _} -> []
    end
  end

  defp check_all_ips([], _host, _port), do: {:error, :dns_resolution_failed}

  defp check_all_ips(ips, host, port) do
    case Enum.find_value(ips, &ip_block_reason/1) do
      nil ->
        Logger.debug("Proxy destination allowed: #{host}:#{port}")
        {:ok, hd(ips)}

      reason ->
        formatted = Enum.map_join(ips, ", ", fn ip -> ip |> :inet.ntoa() |> to_string() end)
        Logger.warning("Proxy destination BLOCKED (#{reason}): #{host}:#{port} resolved to #{formatted}")
        {:error, reason}
    end
  end

  defp ip_block_reason(ip) do
    cond do
      DestinationValidator.localhost_ip?(ip) -> :localhost_blocked
      DestinationValidator.metadata_ip?(ip) -> :metadata_service_blocked
      DestinationValidator.link_local_ip?(ip) -> :link_local_blocked
      true -> nil
    end
  end

  defp normalise_mapped({0, 0, 0, 0, 0, 0xFFFF, ab, cd}) do
    {Bitwise.bsr(ab, 8), Bitwise.band(ab, 0xFF), Bitwise.bsr(cd, 8), Bitwise.band(cd, 0xFF)}
  end

  defp normalise_mapped(ip), do: ip
end
