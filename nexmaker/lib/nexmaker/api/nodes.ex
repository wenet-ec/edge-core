# nexmaker/lib/nexmaker/api/nodes.ex
defmodule Nexmaker.Api.Nodes do
  @moduledoc """
  Node management for Netmaker API.

  Nodes represent a host's membership in a network. Each host can have
  multiple nodes (one per network).

  ## Response shape

      %{
        "id" => "uuid",
        "hostid" => "host-uuid",
        "network" => "cluster-abc",
        "address" => "100.64.0.2/24",
        "address6" => "",
        "connected" => true,
        "pendingdelete" => false,
        "action" => "",
        "lastcheckin" => 1712345678,
        "expdatetime" => 0,
        "isingressgateway" => false,
        "isegressgateway" => false,
        "isrelay" => false,
        "isrelayed" => false,
        "failover" => false,
        "failovernode" => ""
      }

  Network node status shape (`GET /api/v1/nodes/{network}/status`):

      [
        %{
          "id" => "uuid",
          "name" => "hostname",
          "address" => "100.64.0.2/24",
          "connected" => true,
          "lastcheckin" => 1712345678
        }
      ]
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
    - `{:ok, node}` - Node map
    - `{:error, :not_found}` - Node not found
    - `{:error, reason}` - Error occurred
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
  """
  @spec update(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(network_name, node_id, attrs, opts \\ []) do
    Api.request(:put, "/api/nodes/#{network_name}/#{node_id}", Keyword.put(opts, :body, attrs))
  end

  @doc """
  Deletes a node from a network.

  ## Parameters
    - network_name: String - Network name
    - node_id: String - Node ID
    - opts: Keyword - API options (base_url, master_key, force)

  ## Options
    - `:force` - Boolean, immediate hard delete without PendingDelete state (default: true)
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, node_id, opts \\ []) do
    {force, api_opts} = Keyword.pop(opts, :force, true)
    query = if force, do: "?force=true", else: ""
    Api.request(:delete, "/api/nodes/#{network_name}/#{node_id}#{query}", api_opts)
  end

  @doc """
  Bulk deletes multiple nodes from a network.

  Returns 202 Accepted immediately — deletion runs asynchronously on the server.
  The `{:ok, body}` response carries a `%{"Message" => "bulk delete of N node(s) accepted"}`
  confirmation, not a list of deleted nodes.

  ## Parameters
    - network_name: String - Network name
    - node_ids: [String] - List of node UUIDs
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Bulk delete accepted (async, 202)
    - `{:error, {:bad_request, body}}` - Bad body, empty IDs, or network not found
    - `{:error, reason}` - Other error
  """
  @spec bulk_delete(String.t(), [String.t()], keyword()) :: {:ok, any()} | {:error, any()}
  def bulk_delete(network_name, node_ids, opts \\ []) do
    Api.request(
      :delete,
      "/api/v1/nodes/#{network_name}/bulk",
      Keyword.put(opts, :body, %{ids: node_ids})
    )
  end

  @doc """
  Bulk updates the connected/disconnected status of nodes in a network.

  ## Parameters
    - network_name: String - Network name
    - node_ids: [String] - List of node UUIDs to update
    - connected: Boolean - true to connect, false to disconnect
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Status updated
    - `{:error, reason}` - Error occurred
  """
  @spec bulk_update_status(String.t(), [String.t()], boolean(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def bulk_update_status(network_name, node_ids, connected, opts \\ []) do
    Api.request(
      :put,
      "/api/v1/nodes/#{network_name}/bulk/status",
      Keyword.put(opts, :body, %{ids: node_ids, connected: connected})
    )
  end

  @doc """
  Gets connectivity status for all nodes in a network.

  Returns a lightweight status list — not full node objects.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, statuses}` - List of node status maps
    - `{:error, reason}` - Error occurred
  """
  @spec network_status(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def network_status(network_name, opts \\ []) do
    case Api.request(:get, "/api/v1/nodes/#{network_name}/status", opts) do
      {:ok, %{"Response" => statuses}} -> {:ok, statuses}
      other -> other
    end
  end

  @doc """
  Lists nodes in a network via the paginated v1 route `GET /api/v1/nodes/{network}`.

  Supports filtering and pagination. Prefer this over `list/2` for large networks.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options plus optional query params:
      - `:page` - Page number (default: 1)
      - `:per_page` - Page size (default: server default)
      - `:q` - Search string
      - `:os` - OS filter (repeatable)
      - `:status` - Status filter (repeatable)
      - `:device_type` - Device type filter

  ## Returns
    - `{:ok, %{"data" => [...], "page" => _, "per_page" => _, "total" => _, "total_pages" => _}}`
    - `{:error, reason}` - Error occurred
  """
  @spec list_v1(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def list_v1(network_name, opts \\ []) do
    {query_keys, api_opts} =
      Keyword.split(opts, [:page, :per_page, :q, :os, :status, :device_type])

    req_opts = if query_keys == [], do: api_opts, else: Keyword.put(api_opts, :query, query_keys)

    case Api.request(:get, "/api/v1/nodes/#{network_name}", req_opts) do
      {:ok, %{"Response" => paginated}} -> {:ok, paginated}
      other -> other
    end
  end
end
