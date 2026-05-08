# edge_agent/lib/edge_agent/ssh_server/authentication.ex
defmodule EdgeAgent.SshServer.Authentication do
  @moduledoc """
  Handles SSH authentication against EdgeAdmin.

  Both password and public key authentication are verified remotely by
  calling the admin's unified credentials verification endpoint.
  """

  alias EdgeAgent.EdgeClusters.AdminClient

  require Logger

  @doc """
  Password authentication callback for SSH server.
  Validates username/password against EdgeAdmin via remote verification.
  """
  def auth_password(user, password, _peer_address, _state) do
    username = to_string(user)
    password_string = to_string(password)

    Logger.debug("SSH password auth attempt for user: #{username}")

    result =
      case AdminClient.verify_ssh_credentials(username, {:password, password_string}) do
        {:ok, true} ->
          Logger.info("SSH password authentication successful for user: #{username}")
          true

        {:ok, false} ->
          Logger.warning("SSH password authentication failed for user #{username}")
          false

        {:error, reason} ->
          Logger.error("SSH password authentication error for user #{username}: #{inspect(reason)}")
          false
      end

    auth_result =
      if result do
        :success
      else
        :failure
      end

    :telemetry.execute(
      [:edge_agent, :ssh, :authentication],
      %{count: 1, total: 1},
      %{username: username, auth_method: :password, result: auth_result}
    )

    result
  end

  @doc """
  Public key authentication callback for SSH server.
  Formats the key and validates against EdgeAdmin via remote verification.
  """
  def auth_key?(key, user) do
    username = to_string(user)

    Logger.debug("SSH public key auth attempt for user: #{username}")

    # Format the key from Erlang SSH format to OpenSSH string format
    public_key_string = format_public_key(key)

    result =
      if public_key_string == "" do
        Logger.warning("SSH public key auth failed for user #{username}: unsupported key format")
        false
      else
        case AdminClient.verify_ssh_credentials(username, {:public_key, public_key_string}) do
          {:ok, true} ->
            Logger.info("SSH public key authentication successful for user: #{username}")
            true

          {:ok, false} ->
            Logger.warning("SSH public key authentication failed for user #{username}")
            false

          {:error, reason} ->
            Logger.error("SSH public key authentication error for user #{username}: #{inspect(reason)}")

            false
        end
      end

    auth_result =
      if result do
        :success
      else
        :failure
      end

    :telemetry.execute(
      [:edge_agent, :ssh, :authentication],
      %{count: 1, total: 1},
      %{username: username, auth_method: :public_key, result: auth_result}
    )

    result
  end

  # Key formatting (Erlang SSH format -> OpenSSH string)

  @doc false
  # Public for unit testing. Renders a public key (in any of the shapes
  # `:public_key.ssh_decode/2` and `:ssh_file` produce) as an OpenSSH-format
  # string `"<algorithm> <base64>"`. Drift here breaks SSH auth — admin's
  # allow-list comparison runs on this string.
  @spec format_public_key(term()) :: String.t()
  def format_public_key({key_type, key_data, _comment}) when is_list(key_type) and is_binary(key_data) do
    key_type_string = charlist_to_string(key_type)
    key_data_base64 = Base.encode64(key_data)
    "#{key_type_string} #{key_data_base64}"
  end

  # Raw RSA public key from Erlang's public_key module — encode to OpenSSH wire format
  # SSH wire format: length-prefixed "ssh-rsa" + mpint(exponent) + mpint(modulus)
  def format_public_key({:RSAPublicKey, modulus, exponent}) when is_integer(modulus) and is_integer(exponent) do
    type_bin = "ssh-rsa"

    wire =
      ssh_string(type_bin) <>
        ssh_mpint(exponent) <>
        ssh_mpint(modulus)

    "ssh-rsa #{Base.encode64(wire)}"
  end

  def format_public_key({{:ECPoint, point_data}, {:namedCurve, {1, 3, 101, 112}}}) do
    ssh_ed25519_prefix = "ssh-ed25519"
    algorithm_length = byte_size(ssh_ed25519_prefix)
    key_length = byte_size(point_data)

    ssh_wire_format =
      <<algorithm_length::32>> <> ssh_ed25519_prefix <> <<key_length::32>> <> point_data

    key_data_base64 = Base.encode64(ssh_wire_format)
    "ssh-ed25519 #{key_data_base64}"
  end

  def format_public_key({:"ssh-ed25519", key_data}) when is_binary(key_data) do
    key_data_base64 = Base.encode64(key_data)
    "ssh-ed25519 #{key_data_base64}"
  end

  def format_public_key(key) when is_binary(key) do
    String.trim(key)
  end

  def format_public_key(other) do
    Logger.warning("Unknown public key format: #{inspect(other)}")
    ""
  end

  @doc false
  # Public for unit testing. Encode a binary as an SSH length-prefixed string:
  # 4-byte big-endian length followed by the bytes themselves.
  @spec ssh_string(binary()) :: binary()
  def ssh_string(bin) when is_binary(bin) do
    len = byte_size(bin)
    <<len::32>> <> bin
  end

  @doc false
  # Public for unit testing. Encode an integer as an SSH mpint (RFC 4251 §5):
  # big-endian, with a leading 0x00 byte prepended if the high bit is set, so
  # the result is always interpreted as positive.
  @spec ssh_mpint(non_neg_integer()) :: binary()
  def ssh_mpint(0), do: <<0::32>>

  def ssh_mpint(n) when is_integer(n) and n > 0 do
    bin = :binary.encode_unsigned(n)
    # Prepend 0x00 if high bit is set to keep it positive
    bin =
      if :binary.first(bin) >= 0x80 do
        <<0>> <> bin
      else
        bin
      end

    ssh_string(bin)
  end

  @doc false
  # Public for unit testing. Convert SSH key-type charlist to the canonical
  # string. Known types short-circuit; anything else falls through via
  # `List.to_string/1`.
  @spec charlist_to_string(term()) :: String.t()
  def charlist_to_string(charlist) when is_list(charlist) do
    case charlist do
      ~c"ssh-rsa" -> "ssh-rsa"
      ~c"ssh-dss" -> "ssh-dss"
      ~c"ecdsa-sha2-nistp256" -> "ecdsa-sha2-nistp256"
      ~c"ecdsa-sha2-nistp384" -> "ecdsa-sha2-nistp384"
      ~c"ecdsa-sha2-nistp521" -> "ecdsa-sha2-nistp521"
      ~c"ssh-ed25519" -> "ssh-ed25519"
      other -> List.to_string(other)
    end
  end

  def charlist_to_string(other), do: to_string(other)
end
