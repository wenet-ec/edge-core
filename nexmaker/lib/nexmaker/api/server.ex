defmodule Nexmaker.Api.Server do
  @moduledoc """
  Netmaker server info and health check endpoints.

  Provides functions for:
  - Health checks
  - Server status
  - Version info
  - Public IP detection
  - Log retrieval
  """

  @doc """
  Gets Netmaker server status.

  Use this function as a health check - if it returns {:ok, status}, the server is healthy.

  Returns server status information including connection status and version.

  ## Returns
    - `{:ok, status}` - Server status map
    - `{:error, reason}` - Failed to get status

  ## Examples

      {:ok, status} = Nexmaker.Api.Server.status()
  """
  @spec status(keyword()) :: {:ok, map()} | {:error, any()}
  def status(opts \\ []) do
    Nexmaker.Api.request(:get, "/api/server/status", opts)
  end

  @doc """
  Gets Netmaker server info including version.

  Returns server version and configuration information.

  ## Returns
    - `{:ok, info}` - Server info map including version
    - `{:error, reason}` - Failed to get info

  ## Examples

      {:ok, info} = Nexmaker.Api.Server.get_server_info()
      version = info["version"]
  """
  @spec get_server_info(keyword()) :: {:ok, map()} | {:error, any()}
  def get_server_info(opts \\ []) do
    Nexmaker.Api.request(:get, "/api/server/getserverinfo", opts)
  end

  @doc """
  Gets the public IP address as seen by the Netmaker server.

  Useful for discovering the external IP of the requesting machine.

  ## Returns
    - `{:ok, %{"address" => ip}}` - Public IP address
    - `{:error, reason}` - Failed to get IP

  ## Examples

      {:ok, %{"address" => ip}} = Nexmaker.Api.Server.get_public_ip()
  """
  @spec get_public_ip(keyword()) :: {:ok, map()} | {:error, any()}
  def get_public_ip(opts \\ []) do
    Nexmaker.Api.request(:get, "/api/getip", opts)
  end

  @doc """
  Retrieves Netmaker server logs.

  Returns recent server logs.

  ## Returns
    - `{:ok, logs}` - Log entries
    - `{:error, reason}` - Failed to get logs

  ## Examples

      {:ok, logs} = Nexmaker.Api.Server.get_logs()
  """
  @spec get_logs(keyword()) :: {:ok, map()} | {:error, any()}
  def get_logs(opts \\ []) do
    Nexmaker.Api.request(:get, "/api/logs", opts)
  end
end
