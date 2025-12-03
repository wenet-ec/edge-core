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

  defp validate_public_key(provided_key, ssh_public_keys) do
    Logger.debug("Raw provided key format: #{inspect(provided_key, limit: :infinity)}")

    provided_key_string = format_public_key(provided_key)
    provided_key_normalized = normalize_ssh_key(provided_key_string)

    case validate_key_algorithm(provided_key_string) do
      {:ok, algorithm} ->
        Logger.debug("Provided key algorithm: #{algorithm}")
        Logger.debug("Formatted provided key: #{provided_key_string}")
        Logger.debug("Normalized provided key: #{provided_key_normalized}")
        Logger.debug("Against #{length(ssh_public_keys)} stored keys")

        Enum.each(ssh_public_keys, fn stored_key ->
          Logger.debug("Stored key: #{stored_key["public_key"]}")
        end)

        result =
          Enum.any?(ssh_public_keys, fn stored_key ->
            stored_key_string = String.trim(stored_key["public_key"])
            stored_key_normalized = normalize_ssh_key(stored_key_string)

            match = provided_key_normalized == stored_key_normalized

            if match do
              Logger.debug("Key match found for key: #{stored_key["key_name"]}")
            else
              Logger.debug("Key mismatch - provided: #{provided_key_normalized}")
              Logger.debug("Key mismatch - stored: #{stored_key_normalized}")
            end

            match
          end)

        if !result do
          Logger.debug("No matching public key found")
        end

        result

      {:error, reason} ->
        Logger.warning("Unsupported key algorithm: #{reason}")
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

  defp format_public_key({key_type, key_data, _comment}) when is_list(key_type) and is_binary(key_data) do
    key_type_string =
      case key_type do
        ~c"ssh-rsa" -> "ssh-rsa"
        ~c"ssh-dss" -> "ssh-dss"
        ~c"ecdsa-sha2-nistp256" -> "ecdsa-sha2-nistp256"
        ~c"ecdsa-sha2-nistp384" -> "ecdsa-sha2-nistp384"
        ~c"ecdsa-sha2-nistp521" -> "ecdsa-sha2-nistp521"
        ~c"ssh-ed25519" -> "ssh-ed25519"
        other when is_list(other) -> List.to_string(other)
        other -> to_string(other)
      end

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
end
