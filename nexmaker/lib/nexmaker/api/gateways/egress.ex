defmodule Nexmaker.Api.Gateways.Egress do
  @moduledoc """
  Egress gateway management for Netmaker API.

  Egress gateways provide NAT/routing to external networks (non-VPN networks).
  Nodes can route traffic to external IP ranges through an egress gateway.

  ## Use Cases

  - Access local networks around edge nodes (192.168.1.0/24)
  - Route to cloud VPCs or data centers
  - Provide NAT for outbound traffic

  ## Examples

      # Create egress gateway for local network access
      {:ok, node} = Nexmaker.Api.Gateways.Egress.create("cluster-abc", "node-id", %{
        ranges: ["192.168.1.0/24"]
      })

      # Get all egress routes for a network
      {:ok, routes} = Nexmaker.Api.Gateways.Egress.list_routes("cluster-abc")

      # Delete egress gateway
      {:ok, _} = Nexmaker.Api.Gateways.Egress.delete("cluster-abc", "node-id")
  """

  alias Nexmaker.Api

  @doc """
  Creates an egress gateway on a node.

  Configures the specified node as an egress gateway, enabling routing to
  external networks (outside the VPN).

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID to make egress gateway
    - attrs: Map - Gateway attributes (optional):
      - `:ranges` - List of CIDR ranges to route (e.g., ["192.168.1.0/24"])
      - `:nat_enabled` - Boolean - Enable NAT (default: "yes")
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Updated node map with egress gateway config
    - `{:error, reason}` - Error occurred

  ## Examples

      # Create egress to local network
      {:ok, node} = Nexmaker.Api.Gateways.Egress.create("cluster-abc", "node-123", %{
        ranges: ["192.168.1.0/24", "10.0.0.0/8"]
      })
  """
  @spec create(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, node_id, attrs \\ %{}, opts \\ []) do
    Api.request(
      :post,
      "/api/nodes/#{network_name}/#{node_id}/creategateway",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Deletes an egress gateway from a node.

  Removes egress gateway configuration from the specified node.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Egress gateway deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Gateways.Egress.delete("cluster-abc", "node-123")
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, node_id, opts \\ []) do
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}/deletegateway", opts)
  end

  @doc """
  Gets egress routes for a network.

  Returns all egress gateway routes configured in the network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, routes}` - List of egress route maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, routes} = Nexmaker.Api.Gateways.Egress.list_routes("cluster-abc")
  """
  @spec list_routes(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_routes(network_name, opts \\ []) do
    Api.request(:get, "/api/networks/#{network_name}/egress_routes", opts)
  end
end
