# edge_admin/lib/edge_admin/proxy_servers/admin_tunnel/protocol.ex
defmodule EdgeAdmin.ProxyServers.AdminTunnel.Protocol do
  @moduledoc "Authenticated handshake protocol for the private Admin TCP tunnel."

  @magic "EDGE_TUNNEL"
  @version 1
  @mac_size 32

  @spec build_handshake(String.t(), String.t(), 0..65_535) :: binary()
  def build_handshake(secret, target_host, target_port) do
    host = IO.iodata_to_binary(target_host)
    host_size = byte_size(host)
    payload = <<@version, host_size::16, host::binary, target_port::16>>
    mac = :crypto.mac(:hmac, :sha256, secret, payload)
    <<@magic::binary, payload::binary, mac::binary-size(@mac_size)>>
  end

  @spec response(:ok | {:error, term()}) :: binary()
  def response(:ok), do: <<1, 0::16>>
  def response({:error, _reason}), do: <<0, 1::16>>

  @spec validate_handshake(String.t(), binary()) ::
          {:ok, String.t(), 1..65_535} | {:error, term()}
  def validate_handshake(secret, <<@magic::binary, @version, host_size::16, rest::binary>>) do
    required = host_size + 2 + @mac_size

    if byte_size(rest) == required do
      <<host::binary-size(^host_size), port::16, mac::binary-size(@mac_size)>> = rest
      payload = <<@version, host_size::16, host::binary, port::16>>
      expected = :crypto.mac(:hmac, :sha256, secret, payload)

      cond do
        not secure_compare(mac, expected) -> {:error, :unauthorized}
        host == "" -> {:error, :invalid_target}
        port == 0 -> {:error, :invalid_target}
        true -> {:ok, host, port}
      end
    else
      {:error, :invalid_handshake}
    end
  end

  def validate_handshake(_secret, _request), do: {:error, :invalid_handshake}

  defp secure_compare(a, b) when byte_size(a) == byte_size(b), do: :crypto.hash_equals(a, b)

  defp secure_compare(a, b) do
    _ = :crypto.hash_equals(a, String.slice(b <> a, 0, byte_size(a)))
    false
  end
end
