# nexmaker/lib/nexmaker/api/server.ex
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

  ## Options
    - `:retries` - Number of retry attempts on failure (default: 0)
    - `:retry_delay` - Delay in milliseconds between retries (default: 100)
    - Other options passed to `Nexmaker.Api.request/3`

  ## Returns
    - `{:ok, status}` - Server status map
    - `{:error, reason}` - Failed to get status after all retries

  ## Examples

      # Simple health check (no retries)
      {:ok, status} = Nexmaker.Api.Server.status()

      # Health check with retries for transient failures
      {:ok, status} = Nexmaker.Api.Server.status(retries: 2, retry_delay: 200)
  """
  @spec status(keyword()) :: {:ok, map()} | {:error, any()}
  def status(opts \\ []) do
    retries = Keyword.get(opts, :retries, 0)
    retry_delay = Keyword.get(opts, :retry_delay, 100)
    api_opts = Keyword.drop(opts, [:retries, :retry_delay])

    do_request_with_retry(:get, "/api/server/status", api_opts, retries, retry_delay)
  end

  # Private helper for retry logic
  defp do_request_with_retry(method, path, opts, retries_left, retry_delay) do
    case Nexmaker.Api.request(method, path, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when retries_left > 0 ->
        Process.sleep(retry_delay)
        do_request_with_retry(method, path, opts, retries_left - 1, retry_delay)

      {:error, reason} ->
        {:error, reason}
    end
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
    # Note: this endpoint returns a plain-text body (not JSON) on both success
    # and 400 error. Success body is a raw IP string wrapped as %{body: "x.x.x.x"}.
    # On 400, Nexmaker.Api.normalize/1 returns {:error, {:bad_request, "ip is invalid: ..."}}
    # where the body is a binary, not a %{"Message" => ...} map.
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
