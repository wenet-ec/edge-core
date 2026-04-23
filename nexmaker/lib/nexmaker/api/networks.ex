# nexmaker/lib/nexmaker/api/networks.ex
defmodule Nexmaker.Api.Networks do
  @moduledoc """
  Network management for Netmaker API.

  Networks are isolated VPN networks in Netmaker. Each network has its own
  IPv4/IPv6 address range and DNS namespace.

  ## Examples

      # Create a network
      {:ok, network} = Nexmaker.Api.Networks.create("admin-cluster",
        addressrange: "100.64.0.0/24"
      )

      # List all networks
      {:ok, networks} = Nexmaker.Api.Networks.list()

      # Get a specific network
      {:ok, network} = Nexmaker.Api.Networks.get("admin-cluster")

      # Delete a network
      {:ok, _} = Nexmaker.Api.Networks.delete("admin-cluster")
  """

  alias Nexmaker.Api

  @doc """
  Lists all networks.

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, networks}` - List of network maps (empty list if no networks exist)
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, networks} = Nexmaker.Api.Networks.list()
  """
  @spec list(keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(opts \\ []) do
    case Api.request(:get, "/api/networks", opts) do
      {:ok, nil} ->
        # API returns null when no networks exist
        {:ok, []}

      {:ok, networks} when is_list(networks) ->
        {:ok, networks}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new network.

  ## Parameters
    - network_name: String - Unique network name (e.g., "admin-cluster", "cluster-abc-123")
    - attrs: Map - Network attributes (optional):
      - `:addressrange` - IPv4 CIDR (e.g., "100.64.0.0/24")
      - `:addressrange6` - IPv6 CIDR (optional)
      - `:defaultaccesslevel` - Default ACL level (optional)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, network}` - Created network map
    - `{:error, {:bad_request, body}}` - Validation failure (name too long, bad CIDR,
      missing CIDR, or "network cidr already in use" — all come back as 400)

  ## Examples

      {:ok, network} = Nexmaker.Api.Networks.create("admin-cluster",
        addressrange: "100.64.0.0/24"
      )
  """
  @spec create(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, attrs \\ %{}, opts \\ []) do
    body = Map.put(attrs, :netid, network_name)
    Api.request(:post, "/api/networks", Keyword.put(opts, :body, body))
  end

  @doc """
  Gets a specific network by name.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, network}` - Network map
    - `{:error, :not_found}` - Network not found
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, network} = Nexmaker.Api.Networks.get("admin-cluster")
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(network_name, opts \\ []) do
    Api.request(:get, "/api/networks/#{network_name}", opts)
  end

  @doc """
  Updates a network.

  ## Parameters
    - network_name: String - Network name
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, network}` - Updated network map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, network} = Nexmaker.Api.Networks.update("admin-cluster", %{
        defaultaccesslevel: 1
      })
  """
  @spec update(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(network_name, attrs, opts \\ []) do
    Api.request(:put, "/api/networks/#{network_name}", Keyword.put(opts, :body, attrs))
  end

  @doc """
  Deletes a network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key, force)

  ## Options
    - `:force` - Boolean, bypass the "network still has nodes" check (default: true).
      With `force: false`, Netmaker returns 403 if the network has active nodes.
      With `force: true` (default), deletion always proceeds.

  ## Returns
    - `{:ok, response}` - Network deleted
    - `{:error, {:bad_request, body}}` - Validation error
    - `{:error, :service_unavailable}` - DB error or 403 (nodes still present with force: false)

  ## Examples

      {:ok, _} = Nexmaker.Api.Networks.delete("old-cluster")
      {:ok, _} = Nexmaker.Api.Networks.delete("old-cluster", force: false)
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, opts \\ []) do
    {force, api_opts} = Keyword.pop(opts, :force, true)

    query_params = if force, do: "?force=true", else: ""

    Api.request(:delete, "/api/networks/#{network_name}#{query_params}", api_opts)
  end

  @doc """
  Gets statistics for all networks.

  Returns node count, host count, and connectivity info per network.

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, stats}` - Map of network_name => stats
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, stats} = Nexmaker.Api.Networks.stats()
  """
  @spec stats(keyword()) :: {:ok, map()} | {:error, any()}
  def stats(opts \\ []) do
    case Api.request(:get, "/api/v1/networks/stats", opts) do
      {:ok, %{"Response" => data}} when not is_nil(data) -> {:ok, data}
      {:ok, %{"Response" => nil}} -> {:ok, %{}}
      other -> other
    end
  end

  @doc """
  Gets egress routes for a network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, routes}` - Map of node_id => [cidr, ...]
    - `{:error, reason}` - Error occurred
  """
  @spec egress_routes(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def egress_routes(network_name, opts \\ []) do
    case Api.request(:get, "/api/networks/#{network_name}/egress_routes", opts) do
      {:ok, %{"Response" => routes}} -> {:ok, routes}
      other -> other
    end
  end
end
