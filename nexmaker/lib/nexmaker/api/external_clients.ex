defmodule Nexmaker.Api.ExternalClients do
  @moduledoc """
  External client (Remote Access Client) management for Netmaker API.

  External clients are remote access clients (laptops, phones, etc.) that connect
  to a network via an ingress gateway without running full netclient. They use
  standard WireGuard clients with configuration files.

  ## Use Cases

  - Remote access for end users (laptops, phones)
  - Developer access to edge networks
  - Third-party service integration
  - Mobile device VPN access

  ## External Client Lifecycle

  1. Create ingress gateway on a node
  2. Create external client on the ingress gateway
  3. Download WireGuard config file
  4. Import config into WireGuard client
  5. Connect to network

  ## Examples

      # Create external client on ingress gateway
      {:ok, client} = Nexmaker.Api.ExternalClients.create("cluster-abc", "ingress-node-id", %{
        client_id: "laptop-john"
      })

      # List all external clients
      {:ok, clients} = Nexmaker.Api.ExternalClients.list()

      # Get client details
      {:ok, client} = Nexmaker.Api.ExternalClients.get("cluster-abc", "client-id")

      # Get WireGuard config file
      {:ok, config} = Nexmaker.Api.ExternalClients.get_config("cluster-abc", "client-id", "file")

      # Delete external client
      {:ok, _} = Nexmaker.Api.ExternalClients.delete("cluster-abc", "client-id")
  """

  alias Nexmaker.Api

  @doc """
  Lists all external clients across all networks.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, clients}` - List of external client maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, clients} = Nexmaker.Api.ExternalClients.list()
  """
  @spec list(keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(opts \\ []) do
    Api.request(:get, "/api/extclients", opts)
  end

  @doc """
  Lists external clients in a specific network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, clients}` - List of external client maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, clients} = Nexmaker.Api.ExternalClients.list_by_network("cluster-abc")
  """
  @spec list_by_network(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_by_network(network_name, opts \\ []) do
    Api.request(:get, "/api/extclients/#{network_name}", opts)
  end

  @doc """
  Creates an external client on an ingress gateway.

  The node must be configured as an ingress gateway before creating external clients.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Ingress gateway node ID
    - attrs: Map - Client attributes:
      - `:client_id` - Unique client identifier (required)
      - `:public_key` - WireGuard public key (optional, auto-generated if not provided)
      - `:dns` - DNS servers for client (optional)
      - `:extra_allowed_ips` - Additional allowed IPs (optional)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, client}` - Created external client map (includes config)
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, client} = Nexmaker.Api.ExternalClients.create("cluster-abc", "ingress-node-id", %{
        client_id: "laptop-alice",
        dns: ["1.1.1.1", "8.8.8.8"]
      })
  """
  @spec create(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, node_id, attrs, opts \\ []) do
    Api.request(
      :post,
      "/api/extclients/#{network_name}/#{node_id}",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Gets an external client by ID.

  ## Parameters
    - network_name: String - Network name
    - client_id: String - External client ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, client}` - External client map
    - `{:error, :not_found}` - Client not found
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, client} = Nexmaker.Api.ExternalClients.get("cluster-abc", "laptop-alice")
  """
  @spec get(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(network_name, client_id, opts \\ []) do
    Api.request(:get, "/api/extclients/#{network_name}/#{client_id}", opts)
  end

  @doc """
  Updates an external client.

  ## Parameters
    - network_name: String - Network name
    - client_id: String - External client ID
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, client}` - Updated external client map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, client} = Nexmaker.Api.ExternalClients.update("cluster-abc", "laptop-alice", %{
        dns: ["1.1.1.1"]
      })
  """
  @spec update(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(network_name, client_id, attrs, opts \\ []) do
    Api.request(
      :put,
      "/api/extclients/#{network_name}/#{client_id}",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Deletes an external client.

  ## Parameters
    - network_name: String - Network name
    - client_id: String - External client ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Client deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.ExternalClients.delete("cluster-abc", "laptop-alice")
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, client_id, opts \\ []) do
    Api.request(:delete, "/api/extclients/#{network_name}/#{client_id}", opts)
  end

  @doc """
  Gets external client configuration file.

  Downloads the WireGuard configuration for an external client.

  ## Parameters
    - network_name: String - Network name
    - client_id: String - External client ID
    - config_type: String - Configuration type ("wireguard", "file", or other formats)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, config}` - Configuration data (format depends on config_type)
    - `{:error, reason}` - Error occurred

  ## Examples

      # Get as file download
      {:ok, config} = Nexmaker.Api.ExternalClients.get_config("cluster-abc", "laptop-alice", "file")

      # Get WireGuard format
      {:ok, config} = Nexmaker.Api.ExternalClients.get_config("cluster-abc", "laptop-alice", "wireguard")
  """
  @spec get_config(String.t(), String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def get_config(network_name, client_id, config_type, opts \\ []) do
    Api.request(:get, "/api/extclients/#{network_name}/#{client_id}/#{config_type}", opts)
  end

  @doc """
  Gets HA (High Availability) configuration for external clients.

  Returns configuration that supports multiple ingress gateways for failover.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, config}` - HA configuration data
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, ha_config} = Nexmaker.Api.ExternalClients.get_ha_config("cluster-abc")
  """
  @spec get_ha_config(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def get_ha_config(network_name, opts \\ []) do
    Api.request(:get, "/api/v1/client_conf/#{network_name}", opts)
  end
end
