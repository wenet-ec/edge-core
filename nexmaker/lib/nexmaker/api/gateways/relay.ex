# nexmaker/lib/nexmaker/api/gateways/relay.ex
defmodule Nexmaker.Api.Gateways.Relay do
  @moduledoc """
  Relay node management for Netmaker API.

  Relay nodes help nodes communicate when they can't establish direct connections
  (e.g., behind NAT, firewall restrictions). Traffic is relayed through the relay node.

  ## Use Cases

  - NAT traversal for nodes behind restrictive firewalls
  - Connectivity for nodes without public IPs
  - Fallback routing when direct connections fail

  ## Examples

      # Create relay node
      {:ok, node} = Nexmaker.Api.Gateways.Relay.create("cluster-abc", "node-id", %{
        relayed_nodes: ["node-2-id", "node-3-id"]
      })

      # Delete relay
      {:ok, _} = Nexmaker.Api.Gateways.Relay.delete("cluster-abc", "node-id")
  """

  alias Nexmaker.Api

  @doc """
  Creates a relay node.

  Configures the specified node as a relay, allowing it to forward traffic
  for nodes that can't establish direct connections.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID to make relay
    - attrs: Map - Relay attributes (optional):
      - `:relayed_nodes` - List of node IDs to relay for
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map with relay config
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Gateways.Relay.create("cluster-abc", "relay-node-id", %{
        relayed_nodes: ["node-a-id", "node-b-id"]
      })
  """
  @spec create(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, node_id, attrs \\ %{}, opts \\ []) do
    Api.request(
      :post,
      "/api/nodes/#{network_name}/#{node_id}/createrelay",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Deletes a relay node.

  Removes relay configuration from the specified node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Relay deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Gateways.Relay.delete("cluster-abc", "relay-node-id")
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, node_id, opts \\ []) do
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}/deleterelay", opts)
  end

  @doc """
  Assigns a node to a relay gateway.

  Configures the specified node to use a relay gateway for connectivity.
  Only the last assignment matters - assigning to a new gateway overwrites the previous one.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID to assign to gateway
    - gateway_node_id: String - Gateway node ID to relay through
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map with relay configuration
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Gateways.Relay.assign("cluster-abc", "agent-node-id", "gateway-node-id")
  """
  @spec assign(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def assign(network_name, node_id, gateway_node_id, opts \\ []) do
    Api.request(
      :post,
      "/api/nodes/#{network_name}/#{node_id}/gateway/assign?gw_id=#{gateway_node_id}",
      opts
    )
  end

  @doc """
  Unassigns a node from its relay gateway.

  Removes relay gateway assignment from the specified node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID to unassign
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map without relay
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.Gateways.Relay.unassign("cluster-abc", "agent-node-id")
  """
  @spec unassign(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def unassign(network_name, node_id, opts \\ []) do
    Api.request(:post, "/api/nodes/#{network_name}/#{node_id}/gateway/unassign", opts)
  end
end
