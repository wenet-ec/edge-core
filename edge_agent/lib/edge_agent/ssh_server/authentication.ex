# edge_agent/lib/edge_agent/ssh_server/authentication.ex
defmodule EdgeAgent.SshServer.Authentication do
  @moduledoc """
  Handles SSH authentication against EdgeAdmin.
  """

  alias EdgeAgent.EdgeClusters.AdminClient

  require Logger

  @supported_algorithms [
    "ssh-ed25519",
    "ecdsa-sha2-nistp256",
    "ecdsa-sha2-nistp384",
    "ecdsa-sha2-nistp521",
    "ssh-rsa",
    "ssh-dss"
  ]

  @doc """
  Password authentication callback for SSH server.
  Validates username/password against EdgeAdmin via remote verification.
  """
  def auth_password(user, password, _peer_address, _state) do
    username = to_string(user)
    password_string = to_string(password)

    Logger.debug("SSH password auth attempt for user: #{username}")

    case AdminClient.verify_ssh_password(username, password_string) do
      {:ok, true} ->
        Logger.info("SSH password authentication successful for user: #{username}")
        true

      {:ok, false} ->
        Logger.warning(
          "SSH password authentication failed for user #{username}: verification returned false"
        )

        false

      {:error, reason} ->
        Logger.error("SSH password authentication error for user #{username}: #{inspect(reason)}")
        false
    end
  end

  @doc """
  Public key authentication callback for SSH server.
  Validates public key against EdgeAdmin SSH public keys.
  """
  def auth_key?(key, user) do
    Logger.debug("SSH auth attempt for user: #{user}")

    with {:ok, ssh_usernames} <- AdminClient.list_ssh_usernames(),
         {:ok, ssh_username} <- find_username(ssh_usernames, to_string(user)),
         ssh_public_keys <- ssh_username["public_keys"] || [],
         true <- validate_public_key(key, ssh_public_keys) do
      Logger.info("SSH authentication successful for user: #{user}")
      true
    else
      {:error, reason} ->
        Logger.warning("SSH authentication failed for user #{user}: #{inspect(reason)}")
        false

      false ->
        Logger.warning("SSH authentication failed for user #{user}: public key not found")
        false
    end
  end

  # Private functions

  defp find_username(ssh_usernames, username) do
    case Enum.find(ssh_usernames, fn u -> u["username"] == username end) do
      nil ->
        Logger.debug("Username '#{username}' not found in SSH usernames")
        {:error, :username_not_found}

      ssh_username ->
        Logger.debug("Found SSH username: #{ssh_username["id"]}")
        {:ok, ssh_username}
    end
  end

  defp validate_public_key(_provided_key, []) do
    Logger.debug("No public keys configured for user")
    false
  end

  defp validate_public_key(provided_key, ssh_public_keys) do
    Logger.debug("Validating public key against #{length(ssh_public_keys)} stored key(s)")

    provided_key_string = format_public_key(provided_key)
    provided_key_normalized = normalize_ssh_key(provided_key_string)

    case validate_key_algorithm(provided_key_string) do
      {:ok, algorithm} ->
        Logger.debug(
          "Provided key: #{algorithm} #{String.slice(provided_key_normalized, 0..50)}..."
        )

        result =
          Enum.find_value(ssh_public_keys, false, fn stored_key ->
            stored_key_normalized =
              stored_key["public_key"]
              |> String.trim()
              |> normalize_ssh_key()

            if provided_key_normalized == stored_key_normalized do
              Logger.debug("Key match found: #{stored_key["key_name"]}")
              true
            else
              false
            end
          end)

        if !result do
          Logger.debug("No matching public key found")
        end

        result

      {:error, reason} ->
        Logger.warning("Invalid key: #{reason}")
        false
    end
  end

  defp validate_key_algorithm(key_string) do
    case String.split(key_string, " ", parts: 2) do
      [algorithm, _key_data] when algorithm in @supported_algorithms ->
        {:ok, algorithm}

      [algorithm, _key_data] ->
        {:error, "unsupported algorithm: #{algorithm}"}

      _ ->
        {:error, "invalid key format"}
    end
  end

  defp normalize_ssh_key(key_string) do
    case String.split(key_string, " ", parts: 3) do
      [algorithm, key_data, _comment] -> "#{algorithm} #{key_data}"
      [algorithm, key_data] -> "#{algorithm} #{key_data}"
      _ -> key_string
    end
  end

  defp format_public_key({key_type, key_data, _comment})
       when is_list(key_type) and is_binary(key_data) do
    key_type_string = charlist_to_string(key_type)
    key_data_base64 = Base.encode64(key_data)
    "#{key_type_string} #{key_data_base64}"
  end

  defp format_public_key({{:ECPoint, point_data}, {:namedCurve, {1, 3, 101, 112}}}) do
    ssh_ed25519_prefix = "ssh-ed25519"
    algorithm_length = byte_size(ssh_ed25519_prefix)
    key_length = byte_size(point_data)

    ssh_wire_format =
      <<algorithm_length::32>> <> ssh_ed25519_prefix <> <<key_length::32>> <> point_data

    key_data_base64 = Base.encode64(ssh_wire_format)
    "ssh-ed25519 #{key_data_base64}"
  end

  defp format_public_key({:"ssh-ed25519", key_data}) when is_binary(key_data) do
    key_data_base64 = Base.encode64(key_data)
    "ssh-ed25519 #{key_data_base64}"
  end

  defp format_public_key(key) when is_binary(key) do
    String.trim(key)
  end

  defp format_public_key(other) do
    Logger.warning("Unknown public key format: #{inspect(other)}")
    Logger.debug("Key format details: #{inspect(other, limit: :infinity)}")
    ""
  end

  # Helper to convert SSH key type charlist to string
  defp charlist_to_string(charlist) when is_list(charlist) do
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

  defp charlist_to_string(other), do: to_string(other)
end
