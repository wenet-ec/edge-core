# nexmaker/lib/nexmaker/api/advanced_egress.ex
defmodule Nexmaker.Api.AdvancedEgress do
  @moduledoc """
  Advanced egress gateway management for Netmaker API.

  Advanced egress provides resource-centric egress management with enhanced features
  compared to basic egress (Gateways.Egress):

  - Resource-centric vs node-centric (multiple nodes can serve same egress route)
  - Route metrics (priority/preference for multi-path routing)
  - Domain-based routing (egress routes can target domains, not just IP ranges)
  - Advanced NAT options (per-route NAT control)

  ## Use Cases

  - Multi-path routing with failover (multiple nodes serving same egress)
  - Domain-based egress (route *.example.com through specific gateway)
  - Advanced NAT configurations per route
  - Route metrics for traffic engineering

  ## Examples

      # Create advanced egress route
      {:ok, egress} = Nexmaker.Api.AdvancedEgress.create(%{
        network: "cluster-abc",
        ranges: ["192.168.1.0/24"],
        node_id: "node-123",
        nat_enabled: "yes"
      })

      # List all advanced egress routes
      {:ok, routes} = Nexmaker.Api.AdvancedEgress.list()

      # Update egress route
      {:ok, egress} = Nexmaker.Api.AdvancedEgress.update(egress_id, %{
        ranges: ["192.168.0.0/16"]
      })

      # Delete egress route
      {:ok, _} = Nexmaker.Api.AdvancedEgress.delete(egress_id)
  """

  alias Nexmaker.Api

  @doc """
  Creates an advanced egress route.

  Creates a resource-centric egress route with advanced configuration options.

  ## Parameters
    - attrs: Map - Egress attributes:
      - `:network` - Network name (required)
      - `:ranges` - List of CIDR ranges or domains (required)
      - `:node_id` - Node ID to serve egress (required)
      - `:nat_enabled` - Enable NAT ("yes"/"no", default: "yes")
      - `:metric` - Route metric/priority (optional)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, egress}` - Created egress route map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, egress} = Nexmaker.Api.AdvancedEgress.create(%{
        network: "cluster-abc",
        ranges: ["192.168.1.0/24", "*.internal.example.com"],
        node_id: "node-123",
        nat_enabled: "yes",
        metric: 100
      })
  """
  @spec create(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(attrs, opts \\ []) do
    case Api.request(:post, "/api/v1/egress", Keyword.put(opts, :body, attrs)) do
      {:ok, %{"Response" => egress}} -> {:ok, egress}
      other -> other
    end
  end

  @doc """
  Lists advanced egress routes for a network.

  ## Parameters
    - network_name: String - Network name (required)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, egress_routes}` - List of egress route maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, routes} = Nexmaker.Api.AdvancedEgress.list("cluster-abc")
  """
  @spec list(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(network_name, opts \\ []) do
    case Api.request(:get, "/api/v1/egress?network=#{network_name}", opts) do
      {:ok, %{"Response" => egresses}} -> {:ok, egresses}
      other -> other
    end
  end

  @doc """
  Updates an advanced egress route.

  Updates configuration for an existing advanced egress route.

  ## Parameters
    - egress_id: String - Egress route ID
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, egress}` - Updated egress route map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, egress} = Nexmaker.Api.AdvancedEgress.update("egress-id", %{
        ranges: ["10.0.0.0/8"],
        metric: 200
      })
  """
  @spec update(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(egress_id, attrs, opts \\ []) do
    body = Map.put(attrs, :id, egress_id)
    case Api.request(:put, "/api/v1/egress", Keyword.put(opts, :body, body)) do
      {:ok, %{"Response" => egress}} -> {:ok, egress}
      other -> other
    end
  end

  @doc """
  Deletes an advanced egress route.

  Removes an advanced egress route configuration.

  ## Parameters
    - egress_id: String - Egress route ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Egress route deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.AdvancedEgress.delete("egress-id")
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(egress_id, opts \\ []) do
    Api.request(:delete, "/api/v1/egress?id=#{egress_id}", opts)
  end
end
