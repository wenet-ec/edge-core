# edge_agent/lib/edge_agent/ingress_tunneling/stun.ex
defmodule EdgeAgent.IngressTunneling.Stun do
  @moduledoc "Discovers a server-reflexive IPv4 UDP candidate through STUN Binding requests."

  import Bitwise

  @magic 0x2112A442
  @transaction_size 12

  @spec discover(:inet.socket(), [String.t()]) :: [String.t()]
  def discover(socket, servers) do
    servers
    |> Enum.reduce([], fn server, candidates ->
      case discover_from(socket, server) do
        {:ok, candidate} -> [candidate | candidates]
        :error -> candidates
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  @doc "Decodes a STUN Binding response only when its transaction ID matches."
  @spec mapped_address(binary(), binary()) :: {:ok, :inet.ip4_address(), :inet.port_number()} | :error
  def mapped_address(
        <<0x01, 0x01, length::unsigned-big-16, @magic::unsigned-big-32, transaction::binary-size(@transaction_size),
          attributes::binary>>,
        expected_transaction
      ) do
    if transaction == expected_transaction and length == byte_size(attributes),
      do: parse_attributes(attributes),
      else: :error
  end

  def mapped_address(_packet, _transaction), do: :error

  defp discover_from(socket, server) do
    with {:ok, host, port} <- parse_server(server),
         {:ok, address} <- :inet.getaddr(String.to_charlist(host), :inet),
         transaction = :crypto.strong_rand_bytes(@transaction_size),
         request = <<0x01, 0::unsigned-big-16, @magic::unsigned-big-32, transaction::binary>>,
         :ok <- :gen_udp.send(socket, address, port, request),
         {:ok, {_server_ip, _server_port, response}} <- :gen_udp.recv(socket, 0, 2_000),
         {:ok, mapped_ip, mapped_port} <- mapped_address(response, transaction) do
      {:ok, "#{:inet.ntoa(mapped_ip)}:#{mapped_port}"}
    else
      _ -> :error
    end
  end

  defp parse_server("[" <> rest) do
    case String.split(rest, "]:", parts: 2) do
      [host, port] -> parse_port(host, port)
      _ -> :error
    end
  end

  defp parse_server(server) do
    case String.split(server, ":", parts: 2) do
      [host, port] when host != "" -> parse_port(host, port)
      _ -> :error
    end
  end

  defp parse_port(host, raw_port) do
    case Integer.parse(raw_port) do
      {port, ""} when port in 1..65_535 -> {:ok, host, port}
      _ -> :error
    end
  end

  defp parse_attributes(<<>>), do: :error

  defp parse_attributes(<<type::unsigned-big-16, length::unsigned-big-16, rest::binary>>)
       when byte_size(rest) >= length do
    <<value::binary-size(^length), remaining::binary>> = rest
    padding = rem(4 - rem(length, 4), 4)

    cond do
      byte_size(remaining) < padding ->
        :error

      type == 0x0020 ->
        parse_xor_mapped(value)

      true ->
        <<_padding::binary-size(^padding), attributes::binary>> = remaining
        parse_attributes(attributes)
    end
  end

  defp parse_attributes(_attributes), do: :error

  defp parse_xor_mapped(<<0, 1, xor_port::unsigned-big-16, xor_address::unsigned-big-32>>) do
    port = bxor(xor_port, @magic >>> 16)
    address = bxor(xor_address, @magic)

    if port in 1..65_535 do
      {:ok, {address >>> 24, band(address >>> 16, 0xFF), band(address >>> 8, 0xFF), band(address, 0xFF)}, port}
    else
      :error
    end
  end

  defp parse_xor_mapped(_value), do: :error
end
