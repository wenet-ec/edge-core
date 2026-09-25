# edge_agent/lib/edge_agent_proxy/authentication.ex
defmodule EdgeAgentProxy.Authentication do
  @moduledoc """
  Authenticates Agent proxy credentials.

  The username must be `_` and the password must match the value stored in
  session settings. Comparison is timing-safe. Authentication can be disabled
  for local development, in which case username and password checks are
  bypassed.
  """

  alias EdgeAgent.Settings

  require Logger

  @doc """
  Authenticate proxy request.

  Returns :ok if credentials are valid, {:error, reason} otherwise.
  If authentication is disabled, always returns :ok.
  """
  def authenticate(username, password) do
    auth_enabled = Application.get_env(:edge_agent, :agent_proxy_auth_enabled, true)

    if auth_enabled do
      authenticate_credentials(username, password)
    else
      Logger.debug("Proxy authentication bypassed (auth disabled)")
      :ok
    end
  end

  defp authenticate_credentials(username, password) do
    case Settings.get_proxy_password() do
      nil ->
        Logger.warning("Proxy authentication failed: no password configured")
        {:error, :no_password_configured}

      stored_password ->
        if valid_credentials?(username, password, stored_password) do
          :ok
        else
          Logger.warning("Proxy authentication failed: invalid credentials")
          {:error, :invalid_credentials}
        end
    end
  end

  @doc false
  @spec valid_credentials?(term(), term(), term()) :: boolean()
  def valid_credentials?(username, password, stored_password) when is_binary(stored_password),
    do: username == "_" and secure_compare(to_string(password), stored_password)

  def valid_credentials?(_username, _password, _stored_password), do: false

  # Constant-time binary compare.
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) == byte_size(b) do
      :crypto.hash_equals(a, b)
    else
      _ = :crypto.hash_equals(a, String.slice(b <> a, 0, byte_size(a)))
      false
    end
  end
end
