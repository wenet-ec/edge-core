# edge_agent/lib/edge_agent/proxy_servers/authentication.ex
defmodule EdgeAgent.ProxyServers.Authentication do
  @moduledoc """
  Authentication for proxy server.

  Agent proxy uses simple username/password authentication:
  - Username: "_" (underscore, always)
  - Password: proxy_password from settings table

  Comparison is timing-safe.
  """

  alias EdgeAgent.Settings

  require Logger

  @doc """
  Authenticate proxy request.

  Returns :ok if credentials are valid, {:error, reason} otherwise.
  If authentication is disabled, always returns :ok.
  """
  def authenticate(username, password) do
    auth_enabled = Application.get_env(:edge_agent, :proxy_servers_auth_enabled, true)

    if auth_enabled do
      authenticate_credentials(username, password)
    else
      Logger.debug("Proxy authentication bypassed (auth disabled)")
      :ok
    end
  end

  defp authenticate_credentials(username, password) do
    case Settings.get("proxy_password") do
      nil ->
        Logger.warning("Proxy authentication failed: no password configured")
        {:error, :no_password_configured}

      stored_password ->
        if username == "_" and secure_compare(to_string(password), to_string(stored_password)) do
          :ok
        else
          Logger.warning("Proxy authentication failed: invalid credentials")
          {:error, :invalid_credentials}
        end
    end
  end

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
