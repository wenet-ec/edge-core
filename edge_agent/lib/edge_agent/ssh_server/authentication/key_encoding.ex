# edge_agent/lib/edge_agent/ssh_server/authentication/key_encoding.ex
defmodule EdgeAgent.SshServer.Authentication.KeyEncoding do
  @moduledoc "Pure conversion from Erlang SSH key terms to OpenSSH strings."

  require Logger

  @spec format_public_key(term()) :: String.t()
  def format_public_key({key_type, key_data, _comment}) when is_list(key_type) and is_binary(key_data) do
    "#{charlist_to_string(key_type)} #{Base.encode64(key_data)}"
  end

  def format_public_key({:RSAPublicKey, modulus, exponent}) when is_integer(modulus) and is_integer(exponent) do
    wire = ssh_string("ssh-rsa") <> ssh_mpint(exponent) <> ssh_mpint(modulus)
    "ssh-rsa #{Base.encode64(wire)}"
  end

  def format_public_key({{:ECPoint, point_data}, {:namedCurve, {1, 3, 101, 112}}}) do
    wire = ssh_string("ssh-ed25519") <> ssh_string(point_data)
    "ssh-ed25519 #{Base.encode64(wire)}"
  end

  def format_public_key({:"ssh-ed25519", key_data}) when is_binary(key_data),
    do: "ssh-ed25519 #{Base.encode64(key_data)}"

  def format_public_key(key) when is_binary(key), do: String.trim(key)

  def format_public_key(other) do
    Logger.warning("Unknown public key format: #{inspect(other)}")
    ""
  end

  @spec ssh_string(binary()) :: binary()
  def ssh_string(value), do: <<byte_size(value)::32>> <> value

  @spec ssh_mpint(non_neg_integer()) :: binary()
  def ssh_mpint(0), do: <<0::32>>

  def ssh_mpint(value) when is_integer(value) and value > 0 do
    binary = :binary.encode_unsigned(value)
    binary = if :binary.first(binary) >= 0x80, do: <<0>> <> binary, else: binary
    ssh_string(binary)
  end

  @spec charlist_to_string(term()) :: String.t()
  def charlist_to_string(value) when is_list(value) do
    case value do
      ~c"ssh-rsa" -> "ssh-rsa"
      ~c"ssh-dss" -> "ssh-dss"
      ~c"ecdsa-sha2-nistp256" -> "ecdsa-sha2-nistp256"
      ~c"ecdsa-sha2-nistp384" -> "ecdsa-sha2-nistp384"
      ~c"ecdsa-sha2-nistp521" -> "ecdsa-sha2-nistp521"
      ~c"ssh-ed25519" -> "ssh-ed25519"
      other -> List.to_string(other)
    end
  end

  def charlist_to_string(value), do: to_string(value)
end
