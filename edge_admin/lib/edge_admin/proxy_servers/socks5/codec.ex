# edge_admin/lib/edge_admin/proxy_servers/socks5/codec.ex
defmodule EdgeAdmin.ProxyServers.Socks5.Codec do
  @moduledoc """
  Pure SOCKS5 encoder/decoder (RFC 1928 + RFC 1929) with no I/O.

  Split out so handlers (passive `:gen_tcp.recv`) and `RemoteTunnel`
  (active `{:tcp, socket, data}` messages) can share parsing code.

  Every decoder returns one of:
    * `{:ok, value, rest}` — parsed successfully
    * `{:need_more, required_bytes}` — need at least `required_bytes` more before
      re-parsing; `0` means "keep the current buffer and read more"
    * `{:error, reason}` — protocol violation
  """

  @socks_version 5
  @auth_version 1

  # ATYP
  @atyp_ipv4 1
  @atyp_domain 3
  @atyp_ipv6 4

  @type parse_result(t) :: {:ok, t, binary()} | {:need_more, non_neg_integer()} | {:error, term()}

  @doc """
  Parse a client greeting (`VER NMETHODS METHOD...`). Returns the method list.
  """
  @spec parse_greeting(binary()) :: parse_result([byte()])
  def parse_greeting(<<@socks_version, nmethods, methods::binary-size(nmethods), rest::binary>>) do
    {:ok, :binary.bin_to_list(methods), rest}
  end

  def parse_greeting(<<version, _::binary>>) when version != @socks_version do
    {:error, {:unsupported_version, version}}
  end

  def parse_greeting(buf) when byte_size(buf) < 2, do: {:need_more, 2}
  def parse_greeting(<<_, nmethods, rest::binary>>), do: {:need_more, nmethods - byte_size(rest)}

  @doc """
  Parse a RFC 1929 username/password auth request.
  Returns `{username, password}`.
  """
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

  @doc """
  Parse a SOCKS5 connect request (`VER CMD RSV ATYP ADDR PORT`).
  Returns `{command, host, port}` where `host` is a string (dotted IPv4,
  colon-hex IPv6, or FQDN).
  """
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

  @doc """
  Parse a SOCKS5 server reply (`VER REP RSV ATYP BND.ADDR BND.PORT`).
  Returns `{reply_code, bnd_host, bnd_port}`.
  """
  @spec parse_reply(binary()) :: parse_result({byte(), String.t(), 0..65_535})
  def parse_reply(<<@socks_version, rep, 0, atyp, rest::binary>>) do
    case parse_addr_port(atyp, rest) do
      {:ok, host, port, tail} -> {:ok, {rep, host, port}, tail}
      other -> other
    end
  end

  def parse_reply(<<version, _::binary>>) when version != @socks_version do
    {:error, {:unsupported_version, version}}
  end

  def parse_reply(buf) when byte_size(buf) < 4, do: {:need_more, 4 - byte_size(buf)}

  @doc """
  Parse a RFC 1929 auth response (`VER STATUS`).
  """
  @spec parse_auth_response(binary()) :: parse_result(byte())
  def parse_auth_response(<<@auth_version, status, rest::binary>>), do: {:ok, status, rest}

  def parse_auth_response(<<version, _::binary>>) when version != @auth_version do
    {:error, {:unsupported_auth_version, version}}
  end

  def parse_auth_response(buf) when byte_size(buf) < 2, do: {:need_more, 2 - byte_size(buf)}

  @doc """
  Parse the method-selection reply from an upstream SOCKS5 server (`VER METHOD`).
  """
  @spec parse_method_reply(binary()) :: parse_result(byte())
  def parse_method_reply(<<@socks_version, method, rest::binary>>), do: {:ok, method, rest}

  def parse_method_reply(<<version, _::binary>>) when version != @socks_version,
    do: {:error, {:unsupported_version, version}}

  def parse_method_reply(buf) when byte_size(buf) < 2, do: {:need_more, 2 - byte_size(buf)}

  # Encoders

  @doc """
  Encode a server reply. `bnd_addr` is `{a,b,c,d}`/`{a..h}` tuple or nil (→ 0.0.0.0).
  """
  @spec encode_reply(byte(), :inet.ip_address() | nil, 0..65_535) :: binary()
  def encode_reply(reply_code, bnd_addr, bnd_port) do
    {atyp, addr_bytes} = encode_addr(bnd_addr)
    <<@socks_version, reply_code, 0, atyp, addr_bytes::binary, bnd_port::16>>
  end

  @doc "Encode a greeting method-selection reply."
  def encode_method_reply(method), do: <<@socks_version, method>>

  @doc "Encode an auth status reply."
  def encode_auth_reply(status), do: <<@auth_version, status>>

  @doc """
  Encode a client connect request with a domain-type address.
  """
  def encode_connect_request_domain(host, port) when is_binary(host) and is_integer(port) do
    <<@socks_version, 1, 0, @atyp_domain, byte_size(host)::8, host::binary, port::16>>
  end

  @doc "Encode a client greeting offering username/password auth."
  def encode_greeting_userpass, do: <<@socks_version, 1, 2>>

  @doc "Encode a RFC 1929 auth request."
  def encode_auth_request(username, password) when is_binary(username) and is_binary(password) do
    <<@auth_version, byte_size(username)::8, username::binary, byte_size(password)::8, password::binary>>
  end

  # Address parsing

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
