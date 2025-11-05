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
    - `{:error, reason}` - Error occurred

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
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Network deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Networks.delete("old-cluster")
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, opts \\ []) do
    Api.request(:delete, "/api/networks/#{network_name}", opts)
  end

  @doc """
  Gets network statistics.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, stats}` - Network statistics map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, stats} = Nexmaker.Api.Networks.stats("admin-cluster")
  """
  @spec stats(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def stats(network_name, opts \\ []) do
    Api.request(:get, "/api/networks/#{network_name}/stats", opts)
  end
end
