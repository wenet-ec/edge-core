# edge_agent/lib/edge_agent/ssh_server/authentication.ex
defmodule EdgeAgent.SshServer.Authentication do
  @moduledoc """
  Handles SSH authentication against EdgeAdmin.

  Both password and public key authentication are verified remotely by
  calling the admin's unified credentials verification endpoint.
  """

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.SshServer.Authentication.KeyEncoding

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
    public_key_string = KeyEncoding.format_public_key(key)

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
end
