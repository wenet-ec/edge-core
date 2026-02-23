defmodule Nexmaker.Api.Gateways.Ingress do
  @moduledoc """
  Ingress gateway management for Netmaker API.

  Ingress gateways enable remote access to a network. External clients connect
  to the ingress gateway to access network resources without running full netclient.

  ## Use Cases

  - Remote access for laptops/phones (WireGuard clients)
  - Developer access to edge networks
  - External service integration

  ## Examples

      # Create ingress gateway on a node
      {:ok, node} = Nexmaker.Api.Gateways.Ingress.create("cluster-abc", "node-id")

      # Delete ingress gateway
      {:ok, _} = Nexmaker.Api.Gateways.Ingress.delete("cluster-abc", "node-id")

      # Alternative API style
      {:ok, node} = Nexmaker.Api.Gateways.Ingress.create_gateway("cluster-abc", "node-id")
      {:ok, _} = Nexmaker.Api.Gateways.Ingress.delete_gateway("cluster-abc", "node-id")
  """

  alias Nexmaker.Api

  @doc """
  Creates an ingress gateway on a node.

  Configures the specified node as an ingress gateway, allowing external clients
  to connect to the network through this node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID to make ingress gateway
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map with ingress gateway config
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Gateways.Ingress.create("cluster-abc", "node-123")
  """
  @spec create(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, node_id, opts \\ []) do
    Api.request(:post, "/api/nodes/#{network_name}/#{node_id}/createingress", opts)
  end

  @doc """
  Deletes an ingress gateway from a node.

  Removes ingress gateway configuration from the specified node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Ingress gateway deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Gateways.Ingress.delete("cluster-abc", "node-123")
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, node_id, opts \\ []) do
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}/deleteingress", opts)
  end

  @doc """
  Creates an ingress gateway on a node (alternative endpoint).

  Alternative API endpoint for creating ingress gateways.
  Functionally identical to `create/3`.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - attrs: Map - Gateway attributes (optional):
      - `:relayaddrs` - List of node IDs to relay (default: [])
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map with ingress gateway config
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Gateways.Ingress.create_gateway("cluster-abc", "node-123")
      {:ok, node} = Nexmaker.Api.Gateways.Ingress.create_gateway("cluster-abc", "node-123", %{relayaddrs: []})
  """
  @spec create_gateway(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create_gateway(network_name, node_id, attrs \\ %{}, opts \\ []) do
    # Gateway creation requires a body with relayaddrs (defaults to empty array)
    body = Map.put_new(attrs, :relayaddrs, [])

    Api.request(
      :post,
      "/api/nodes/#{network_name}/#{node_id}/gateway",
      Keyword.put(opts, :body, body)
    )
  end

  @doc """
  Deletes an ingress gateway from a node (alternative endpoint).

  Alternative API endpoint for deleting ingress gateways.
  Functionally identical to `delete/3`.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Ingress gateway deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Gateways.Ingress.delete_gateway("cluster-abc", "node-123")
  """
  @spec delete_gateway(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete_gateway(network_name, node_id, opts \\ []) do
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}/gateway", opts)
  end
end
