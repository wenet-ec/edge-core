defmodule Nexmaker.Api.InternetGateway do
  @moduledoc """
  Internet gateway management for Netmaker API.

  Internet gateways provide full internet routing (0.0.0.0/0) through a VPN node.
  All network traffic from clients goes through the gateway node.

  ## Use Cases

  - Route all internet traffic through VPN (VPN exit node)
  - Bypass geo-restrictions
  - Centralized internet access for remote clients
  - Privacy/security routing (all traffic through trusted node)

  ## Internet Gateway vs Egress Gateway

  - **Internet Gateway**: Routes 0.0.0.0/0 (all internet traffic)
  - **Egress Gateway**: Routes specific IP ranges/networks

  ## Examples

      # Create internet gateway
      {:ok, node} = Nexmaker.Api.InternetGateway.create("cluster-abc", "node-id")

      # Update internet gateway configuration
      {:ok, node} = Nexmaker.Api.InternetGateway.update("cluster-abc", "node-id", %{
        enabled: true
      })

      # Delete internet gateway
      {:ok, _} = Nexmaker.Api.InternetGateway.delete("cluster-abc", "node-id")
  """

  alias Nexmaker.Api

  @doc """
  Creates an internet gateway on a node.

  Configures the specified node as an internet gateway, routing all internet
  traffic (0.0.0.0/0) through this node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID to make internet gateway
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map with internet gateway config
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.InternetGateway.create("cluster-abc", "node-123")
  """
  @spec create(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, node_id, opts \\ []) do
    Api.request(:post, "/api/nodes/#{network_name}/#{node_id}/inet_gw", opts)
  end

  @doc """
  Updates an internet gateway configuration.

  Updates internet gateway settings for a node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node} = Nexmaker.Api.InternetGateway.update("cluster-abc", "node-123", %{
        enabled: true
      })
  """
  @spec update(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(network_name, node_id, attrs, opts \\ []) do
    Api.request(
      :put,
      "/api/nodes/#{network_name}/#{node_id}/inet_gw",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Deletes an internet gateway from a node.

  Removes internet gateway configuration from the specified node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Internet gateway deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.InternetGateway.delete("cluster-abc", "node-123")
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, node_id, opts \\ []) do
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}/inet_gw", opts)
  end
end
