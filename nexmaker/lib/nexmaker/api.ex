defmodule Nexmaker.Api do
  @moduledoc """
  HTTP client for Netmaker REST API.

  This module provides the base HTTP client functionality for interacting
  with Netmaker's REST API. All API modules use this as their foundation.

  ## Configuration

  API calls require base_url and master_key:

      # Via Application config (recommended)
      config :nexmaker,
        base_url: "http://netmaker:8081",
        master_key: System.get_env("NETMAKER_MASTER_KEY")

      # Or pass directly to functions
      Nexmaker.Api.Networks.list(
        base_url: "http://netmaker:8081",
        master_key: "your-master-key"
      )

  ## Authentication

  All API requests use MASTER_KEY authentication via Bearer token:

      Authorization: Bearer <NETMAKER_MASTER_KEY>

  ## Modules

  - `Nexmaker.Api.Networks` - Network management (6 endpoints)
  - `Nexmaker.Api.EnrollmentKeys` - Enrollment key management (4 endpoints)
  - `Nexmaker.Api.Hosts` - Host management (11 endpoints)
  - `Nexmaker.Api.Nodes` - Node management (6 endpoints)
  - `Nexmaker.Api.DNS` - DNS management (8 endpoints)
  - `Nexmaker.Api.Superadmin` - Superadmin bootstrap (3 endpoints)

  Additional modules: ACLs, Gateways, Server, etc. (see planning docs)
  """

  require Logger

  @doc """
  Makes an HTTP request to the Netmaker API.

  ## Parameters
    - method: Atom - HTTP method (:get, :post, :put, :delete)
    - path: String - API path (without base URL, e.g., "/api/networks")
    - opts: Keyword - Options including:
      - `:base_url` - Netmaker API base URL (required)
      - `:master_key` - Netmaker master key (required)
      - `:body` - Request body (map, will be JSON-encoded)
      - `:query` - Query parameters (keyword list)

  ## Returns
    - `{:ok, response_body}` - Success, returns decoded JSON
    - `{:error, reason}` - Failure

  ## Examples

      Nexmaker.Api.request(:get, "/api/networks",
        base_url: "http://netmaker:8081",
        master_key: "abc123"
      )
  """
  @spec request(atom(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def request(method, path, opts \\ []) do
    base_url = get_config(:base_url, opts)
    master_key = get_config(:master_key, opts)
    body = Keyword.get(opts, :body)
    query = Keyword.get(opts, :query, [])

    unless base_url && master_key do
      raise ArgumentError, """
      Nexmaker API requires base_url and master_key.

      Either configure them in config.exs:
        config :nexmaker,
          base_url: "http://netmaker:8081",
          master_key: System.get_env("NETMAKER_MASTER_KEY")

      Or pass them as options:
        Nexmaker.Api.request(:get, "/api/networks",
          base_url: "http://netmaker:8081",
          master_key: "your-key"
        )
      """
    end

    url = build_url(base_url, path, query)

    Logger.debug("Nexmaker API request: #{method} #{url}")

    req_opts = [
      method: method,
      url: url,
      auth: {:bearer, master_key},
      retry: false
    ]

    req_opts = if body, do: Keyword.put(req_opts, :json, body), else: req_opts

    case Req.request(req_opts) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        cond do
          is_map(response_body) or is_list(response_body) ->
            # Req already decoded JSON
            {:ok, response_body}

          is_binary(response_body) and response_body != "" ->
            # Try to decode if it's a string
            case Jason.decode(response_body) do
              {:ok, decoded} -> {:ok, decoded}
              {:error, _} -> {:ok, %{body: response_body}}
            end

          true ->
            # Empty or non-JSON response
            {:ok, %{body: response_body}}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("Netmaker API error #{status}: #{inspect(response_body)}")
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, {:http_client_error, reason}}
    end
  end

  # Private helpers

  defp get_config(key, opts) do
    Keyword.get(opts, key) || Application.get_env(:nexmaker, key)
  end

  defp build_url(base_url, path, []) do
    base_url = String.trim_trailing(base_url, "/")
    "#{base_url}#{path}"
  end

  defp build_url(base_url, path, query) when is_list(query) do
    base_url = String.trim_trailing(base_url, "/")
    query_string = URI.encode_query(query)
    "#{base_url}#{path}?#{query_string}"
  end
end
