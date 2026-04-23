# edge_agent/lib/edge_agent/proxy_servers/socks5/codec.ex
defmodule EdgeAgent.ProxyServers.Socks5.Codec do
  @moduledoc """
  Pure SOCKS5 encoder/decoder (RFC 1928 + RFC 1929) with no I/O.

  Every decoder returns one of:
    * `{:ok, value, rest}` — parsed successfully
    * `{:need_more, required_bytes}` — need at least `required_bytes` more before
      re-parsing; `0` means "keep the current buffer and read more"
    * `{:error, reason}` — protocol violation
  """

  @socks_version 5
  @auth_version 1

  @atyp_ipv4 1
  @atyp_domain 3
  @atyp_ipv6 4

  @type parse_result(t) :: {:ok, t, binary()} | {:need_more, non_neg_integer()} | {:error, term()}

  @spec parse_greeting(binary()) :: parse_result([byte()])
  def parse_greeting(<<@socks_version, nmethods, methods::binary-size(nmethods), rest::binary>>) do
    {:ok, :binary.bin_to_list(methods), rest}
  end

  def parse_greeting(<<version, _::binary>>) when version != @socks_version do
    {:error, {:unsupported_version, version}}
  end

  def parse_greeting(buf) when byte_size(buf) < 2, do: {:need_more, 2}
  def parse_greeting(<<_, nmethods, rest::binary>>), do: {:need_more, nmethods - byte_size(rest)}

  @spec parse_auth_request(binary()) :: parse_result({String.t(), String.t()})
  def parse_auth_request(<<@auth_version, ulen, user::binary-size(ulen), plen, pass::binary-size(plen), rest::binary>>) do
    {:ok, {user, pass}, rest}
  end

  def parse_auth_request(<<version, _::binary>>) when version != @auth_version do
    {:error, {:unsupported_auth_version, version}}
  end

  def parse_auth_request(buf) when byte_size(buf) < 2, do: {:need_more, 2}

  def parse_auth_request(<<_, ulen, rest::binary>>) when byte_size(rest) < ulen + 1 do
    {:need_more, ulen + 1 - byte_size(rest)}
  end

  def parse_auth_request(<<_, ulen, _::binary-size(ulen), plen, rest::binary>>) do
    {:need_more, plen - byte_size(rest)}
  end

  @spec parse_connect_request(binary()) :: parse_result({byte(), String.t(), 1..65_535})
  def parse_connect_request(<<@socks_version, cmd, 0, atyp, rest::binary>>) do
    case parse_addr_port(atyp, rest) do
      {:ok, host, port, tail} -> {:ok, {cmd, host, port}, tail}
      other -> other
    end
  end

  def parse_connect_request(<<version, _::binary>>) when version != @socks_version do
    {:error, {:unsupported_version, version}}
  end

  def parse_connect_request(buf) when byte_size(buf) < 4, do: {:need_more, 4 - byte_size(buf)}

  @spec encode_reply(byte(), :inet.ip_address() | nil, 0..65_535) :: binary()
  def encode_reply(reply_code, bnd_addr, bnd_port) do
    {atyp, addr_bytes} = encode_addr(bnd_addr)
    <<@socks_version, reply_code, 0, atyp, addr_bytes::binary, bnd_port::16>>
  end

  def encode_method_reply(method), do: <<@socks_version, method>>

  def encode_auth_reply(status), do: <<@auth_version, status>>

  defp parse_addr_port(@atyp_ipv4, <<a, b, c, d, port::16, rest::binary>>) do
    {:ok, "#{a}.#{b}.#{c}.#{d}", port, rest}
  end

  defp parse_addr_port(@atyp_ipv4, buf), do: {:need_more, 6 - byte_size(buf)}

  defp parse_addr_port(@atyp_ipv6, <<addr::binary-size(16), port::16, rest::binary>>) do
    <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>> = addr

    host =
      Enum.map_join(
        [a, b, c, d, e, f, g, h],
        ":",
        &(&1 |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
      )

    {:ok, host, port, rest}
  end

  defp parse_addr_port(@atyp_ipv6, buf), do: {:need_more, 18 - byte_size(buf)}

  defp parse_addr_port(@atyp_domain, <<len, host::binary-size(len), port::16, rest::binary>>) do
    {:ok, host, port, rest}
  end

  defp parse_addr_port(@atyp_domain, <<len, rest::binary>>) when byte_size(rest) < len + 2 do
    {:need_more, len + 2 - byte_size(rest)}
  end

  defp parse_addr_port(@atyp_domain, buf) when byte_size(buf) < 1, do: {:need_more, 1}

  defp parse_addr_port(atyp, _), do: {:error, {:unsupported_address_type, atyp}}

  defp encode_addr(nil), do: {@atyp_ipv4, <<0, 0, 0, 0>>}
  defp encode_addr({a, b, c, d}), do: {@atyp_ipv4, <<a, b, c, d>>}

  defp encode_addr({a, b, c, d, e, f, g, h}) do
    {@atyp_ipv6, <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>}
  end
end
