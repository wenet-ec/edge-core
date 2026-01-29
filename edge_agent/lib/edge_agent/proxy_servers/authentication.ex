# edge_agent/lib/edge_agent/proxy_server/authentication.ex
defmodule EdgeAgent.ProxyServers.Authentication do
  @moduledoc """
  Authentication for proxy server.

  Agent proxy uses simple username/password authentication:
  - Username: "_" (underscore, always)
  - Password: proxy_password from settings table
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
        if username == "_" and password == stored_password do
          :ok
        else
          Logger.warning("Proxy authentication failed: invalid credentials")
          {:error, :invalid_credentials}
        end
    end
  end
end
