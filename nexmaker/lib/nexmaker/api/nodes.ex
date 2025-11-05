defmodule Nexmaker.Api.Nodes do
  @moduledoc """
  Node management for Netmaker API.

  Nodes represent a host's membership in a network. Each host can have
  multiple nodes (one per network).

  ## Examples

      # List all nodes in a network
      {:ok, nodes} = Nexmaker.Api.Nodes.list("admin-cluster")

      # Get a specific node
      {:ok, node} = Nexmaker.Api.Nodes.get("admin-cluster", node_id)

      # Update a node
      {:ok, node} = Nexmaker.Api.Nodes.update("admin-cluster", node_id, %{
        name: "new-name"
      })

      # Delete a node
      {:ok, _} = Nexmaker.Api.Nodes.delete("admin-cluster", node_id)
  """

  alias Nexmaker.Api

  @doc """
  Lists all nodes across all networks.

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, nodes}` - List of all node maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, nodes} = Nexmaker.Api.Nodes.list_all()
  """
  @spec list_all(keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_all(opts \\ []) do
    Api.request(:get, "/api/nodes", opts)
  end

  @doc """
  Lists all nodes in a specific network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, nodes}` - List of node maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, nodes} = Nexmaker.Api.Nodes.list("admin-cluster")
  """
  @spec list(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(network_name, opts \\ []) do
    Api.request(:get, "/api/nodes/#{network_name}", opts)
  end

  @doc """
  Gets a specific node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID (UUID)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Node map (includes `hostid` field for Host UUID)
    - `{:error, :not_found}` - Node not found
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Nodes.get("cluster-abc", "node-123")
  """
  @spec get(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(network_name, node_id, opts \\ []) do
    Api.request(:get, "/api/nodes/#{network_name}/#{node_id}", opts)
  end

  @doc """
  Updates a node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Nodes.update("cluster-abc", node_id, %{
        name: "new-name"
      })
  """
  @spec update(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(network_name, node_id, attrs, opts \\ []) do
    Api.request(
      :put,
      "/api/nodes/#{network_name}/#{node_id}",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Deletes a node from a network.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Node deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Nodes.delete("old-cluster", node_id)
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, node_id, opts \\ []) do
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}", opts)
  end

  @doc """
  Gets node status/health.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, status}` - Node status map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, status} = Nexmaker.Api.Nodes.status("cluster-abc", node_id)
  """
  @spec status(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def status(network_name, node_id, opts \\ []) do
    Api.request(:get, "/api/nodes/#{network_name}/#{node_id}/status", opts)
  end
end
