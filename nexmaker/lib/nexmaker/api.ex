# nexmaker/lib/nexmaker/api.ex
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

  ### Core VPN
  - `Nexmaker.Api.Networks` - Network management (6 endpoints)
  - `Nexmaker.Api.EnrollmentKeys` - Enrollment key management (4 endpoints)
  - `Nexmaker.Api.Hosts` - Host management (11 endpoints)
  - `Nexmaker.Api.Nodes` - Node management (6 endpoints)
  - `Nexmaker.Api.Server` - Server info and health (4 endpoints)
  - `Nexmaker.Api.Superadmin` - Superadmin bootstrap (3 endpoints)

  ### Management Features
  - `Nexmaker.Api.ACLs` - Network ACLs (3 endpoints)
  - `Nexmaker.Api.DNS` - DNS management (8 endpoints)
  - `Nexmaker.Api.Gateways.Ingress` - Ingress gateways (4 endpoints)
  - `Nexmaker.Api.Gateways.Egress` - Egress gateways (3 endpoints)
  - `Nexmaker.Api.Gateways.Relay` - Relay nodes (2 endpoints)

  ### Advanced Features
  - `Nexmaker.Api.AdvancedEgress` - Advanced egress routes (4 endpoints)
  - `Nexmaker.Api.InternetGateway` - Internet gateways (3 endpoints)
  - `Nexmaker.Api.ExternalClients` - Remote access clients (8 endpoints)

  ### Integration
  - `Nexmaker.Api.EMQX` - EMQX broker integration (1 endpoint)
  """

  require Logger

  @doc """
  Normalizes a raw Nexmaker API result into a clean semantic error.

  Call this in `vpn.ex` (or any consumer) instead of inspecting raw
  `{:error, {:http_error, status, body}}` tuples directly.

  ## Return values

    - `{:ok, result}` — pass-through, unchanged
    - `{:error, :not_found}` — 404, or 500 with a "no result found" / "could not find" body
    - `{:error, :already_exists}` — 500 with "host already part of network" body
    - `{:error, :conflict}` — 409 Conflict
    - `{:error, {:bad_request, body}}` — 400 Bad Request; body carries the Netmaker message
    - `{:error, :service_unavailable}` — anything else (5xx, network error, etc.)

  ## Examples

      iex> Nexmaker.Api.normalize({:ok, %{"netid" => "cluster-prod"}})
      {:ok, %{"netid" => "cluster-prod"}}

      iex> Nexmaker.Api.normalize({:error, :not_found})
      {:error, :not_found}

      iex> Nexmaker.Api.normalize({:error, {:http_error, 500, %{"Message" => "no result found"}}})
      {:error, :not_found}

      iex> Nexmaker.Api.normalize({:error, {:http_error, 500, %{"Message" => "host already part of network cluster-prod"}}})
      {:error, :already_exists}

      iex> Nexmaker.Api.normalize({:error, {:http_error, 400, %{"Message" => "invalid cidr"}}})
      {:error, {:bad_request, %{"Message" => "invalid cidr"}}}

      iex> Nexmaker.Api.normalize({:error, {:http_error, 409, %{"Message" => "conflict"}}})
      {:error, :conflict}
  """
  @spec normalize({:ok, any()} | {:error, any()}) ::
          {:ok, any()}
          | {:error, :not_found}
          | {:error, :already_exists}
          | {:error, :conflict}
          | {:error, {:bad_request, any()}}
          | {:error, :service_unavailable}
  def normalize({:ok, result}), do: {:ok, result}
  def normalize({:error, :not_found}), do: {:error, :not_found}
  def normalize({:error, :conflict}), do: {:error, :conflict}
  def normalize({:error, {:bad_request, _} = reason}), do: {:error, reason}

  def normalize({:error, {:http_error, 400, body}}), do: {:error, {:bad_request, body}}
  def normalize({:error, {:http_error, 404, _body}}), do: {:error, :not_found}
  def normalize({:error, {:http_error, 409, _body}}), do: {:error, :conflict}

  def normalize({:error, {:http_error, 500, body}}) do
    message = extract_message(body)

    cond do
      netmaker_not_found_message?(message) -> {:error, :not_found}
      netmaker_already_exists_message?(message) -> {:error, :already_exists}
      true -> {:error, :service_unavailable}
    end
  end

  def normalize({:error, _reason}), do: {:error, :service_unavailable}

  # Netmaker returns 500 with these message fragments instead of 404.
  # Remove these clauses as Netmaker fixes individual endpoints to use 404.
  defp netmaker_not_found_message?(msg) do
    String.contains?(msg, "no result found") or
      String.contains?(msg, "could not find any records")
  end

  # Netmaker returns 500 with this message instead of 409 for add-host-to-network.
  # Remove this clause once Netmaker fixes that endpoint.
  defp netmaker_already_exists_message?(msg) do
    String.contains?(msg, "host already part of network")
  end

  @doc """
  Extracts a Netmaker error message from a response body.

  Netmaker error responses are JSON objects of the form `%{"Code" => 400,
  "Message" => "..."}`. Use this to read the message text without re-implementing
  the body shape handling.
  """
  @spec extract_message(any()) :: String.t()
  def extract_message(body) when is_map(body), do: Map.get(body, "Message", "")
  def extract_message(body) when is_binary(body), do: body
  def extract_message(_), do: ""

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
    - `{:error, :not_found}` - 404 response
    - `{:error, :conflict}` - 409 response
    - `{:error, {:bad_request, body}}` - 400 response
    - `{:error, {:http_error, status, body}}` - Other error response
    - `{:error, {:http_client_error, reason}}` - Network/transport failure

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
            {:ok, response_body}

          is_binary(response_body) and response_body != "" ->
            case Jason.decode(response_body) do
              {:ok, decoded} -> {:ok, decoded}
              {:error, _} -> {:ok, %{body: response_body}}
            end

          true ->
            {:ok, %{body: response_body}}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 409, body: response_body}} ->
        Logger.warning("Netmaker API conflict 409: #{inspect(response_body)}")
        {:error, :conflict}

      {:ok, %{status: 400, body: response_body}} ->
        Logger.warning("Netmaker API bad request 400: #{inspect(response_body)}")
        {:error, {:bad_request, response_body}}

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
