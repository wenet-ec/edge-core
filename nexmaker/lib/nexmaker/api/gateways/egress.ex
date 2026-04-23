# nexmaker/lib/nexmaker/api/gateways/egress.ex
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
  @spec list_routes(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def list_routes(network_name, opts \\ []) do
    case Api.request(:get, "/api/networks/#{network_name}/egress_routes", opts) do
      {:ok, %{"Response" => routes}} -> {:ok, routes}
      other -> other
    end
  end

  @doc """
  Lists egress resources for a network.

  Uses `GET /api/v1/egress?network={network_name}`.

  ## Parameters
    - network_name: String - Network name (required)
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec list(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(network_name, opts \\ []) do
    case Api.request(:get, "/api/v1/egress", Keyword.put(opts, :query, network: network_name)) do
      {:ok, %{"Response" => egresses}} -> {:ok, egresses}
      other -> other
    end
  end

  @doc """
  Creates an egress resource.

  Uses `POST /api/v1/egress`.

  ## Parameters
    - attrs: Map - EgressReq body:
      - `network` - Network name (required)
      - `name` - Egress name
      - `range` - CIDR range (e.g. "192.168.1.0/24")
      - `domain` - FQDN (alternative to range)
      - `nat` - Boolean, enable NAT
      - `nodes` - Map of node_id => priority
      - `tags` - Map of tag_id => priority
      - `is_internet_gateway` - Boolean
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec create_v1(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create_v1(attrs, opts \\ []) do
    case Api.request(:post, "/api/v1/egress", Keyword.put(opts, :body, attrs)) do
      {:ok, %{"Response" => egress}} -> {:ok, egress}
      other -> other
    end
  end

  @doc """
  Updates an egress resource.

  Uses `PUT /api/v1/egress`. The `id` field must be included in attrs.

  ## Parameters
    - attrs: Map - EgressReq body with `id` field
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec update_v1(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update_v1(attrs, opts \\ []) do
    case Api.request(:put, "/api/v1/egress", Keyword.put(opts, :body, attrs)) do
      {:ok, %{"Response" => egress}} -> {:ok, egress}
      other -> other
    end
  end

  @doc """
  Deletes an egress resource by ID.

  Uses `DELETE /api/v1/egress?id={id}`.

  ## Parameters
    - id: String - Egress resource ID
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec delete_v1(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete_v1(id, opts \\ []) do
    Api.request(:delete, "/api/v1/egress", Keyword.put(opts, :query, id: id))
  end
end
