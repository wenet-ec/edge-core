# nexmaker/lib/nexmaker/api/hosts.ex
defmodule Nexmaker.Api.Hosts do
  @moduledoc """
  Host management for Netmaker API.

  Hosts represent physical or virtual machines in Netmaker. A single host
  can have multiple nodes (one per network).

  ## Host vs Node
  - **Host** = Physical/virtual machine (registered once, persists across networks)
  - **Node** = Host's membership in a specific network (one node per network)
  """

  alias Nexmaker.Api

  @doc """
  Lists hosts via `GET /api/v1/hosts`. Returns a paginated response.

  ## Query params (pass as opts)
    - `:page` - Page number (default: 1)
    - `:per_page` - Page size, 1–100 (default: 10, clamped to 10 if out of range)
    - `:q` - Search string matched against id, name, public_key, endpoint_ip, endpoint_ipv6
    - `:os` - Filter by OS (e.g. `os: "linux"`); repeatable for multiple values

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, %{"data" => [...], "page" => _, "per_page" => _, "total" => _, "total_pages" => _}}`
    - `{:error, reason}`
  """
  @spec list(keyword()) :: {:ok, map()} | {:error, any()}
  def list(opts \\ []) do
    case Api.request(:get, "/api/v1/hosts", opts) do
      {:ok, %{"Response" => paginated}} -> {:ok, paginated}
      other -> other
    end
  end

  @doc """
  Gets a specific host by ID.

  Uses `GET /api/v1/hosts?q={host_id}` since `GET /api/hosts/{hostid}` was
  removed in v1.5.1 (only PUT/DELETE remain on that path).

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, host}` - Host map
    - `{:error, :not_found}` - Host not found
    - `{:error, reason}` - Error occurred
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(host_id, opts \\ []) do
    with {:ok, %{"data" => hosts}} <- list([q: host_id, per_page: 1] ++ opts) do
      case Enum.find(hosts, fn h -> h["id"] == host_id end) do
        nil -> {:error, :not_found}
        host -> {:ok, host}
      end
    end
  end

  @doc """
  Updates a host.

  ## Parameters
    - host_id: String - Host UUID
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, host}` - Updated host map
    - `{:error, reason}` - Error occurred
  """
  @spec update(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(host_id, attrs, opts \\ []) do
    Api.request(:put, "/api/hosts/#{host_id}", Keyword.put(opts, :body, attrs))
  end

  @doc """
  Deletes a host and all its nodes.

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key, force)

  ## Options
    - `:force` - Boolean - Force delete even if host has nodes (default: true)
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(host_id, opts \\ []) do
    {force, api_opts} = Keyword.pop(opts, :force, true)
    Api.request(:delete, "/api/hosts/#{host_id}?force=#{force}", api_opts)
  end

  @doc """
  Bulk deletes multiple hosts by ID.

  Accepted immediately (202) — deletion runs asynchronously on the server.

  ## Parameters
    - host_ids: [String] - List of host UUIDs
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Bulk delete accepted
    - `{:error, reason}` - Error occurred
  """
  @spec bulk_delete([String.t()], keyword()) :: {:ok, any()} | {:error, any()}
  def bulk_delete(host_ids, opts \\ []) do
    Api.request(:delete, "/api/v1/hosts/bulk", Keyword.put(opts, :body, %{ids: host_ids}))
  end

  @doc """
  Adds a host to a network (creates a node).

  ## Parameters
    - host_id: String - Host UUID
    - network_name: String - Network name to join
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, node}` - Created node map
    - `{:error, reason}` - Error occurred
  """
  @spec add_to_network(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def add_to_network(host_id, network_name, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/networks/#{network_name}", opts)
  end

  @doc """
  Removes a host from a network (deletes the node).

  ## Parameters
    - host_id: String - Host UUID
    - network_name: String - Network name to leave
    - opts: Keyword - API options (base_url, master_key, force)

  ## Options
    - `:force` - Boolean, immediate hard delete without PendingDelete state (default: true)
  """
  @spec remove_from_network(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def remove_from_network(host_id, network_name, opts \\ []) do
    {force, api_opts} = Keyword.pop(opts, :force, true)
    query = if force, do: "?force=true", else: ""
    Api.request(:delete, "/api/hosts/#{host_id}/networks/#{network_name}#{query}", api_opts)
  end

  @doc """
  Regenerates WireGuard keys for a host.

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec regenerate_keys(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def regenerate_keys(host_id, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/keys", opts)
  end

  @doc """
  Regenerates WireGuard keys for all hosts.
  """
  @spec regenerate_all_keys(keyword()) :: {:ok, any()} | {:error, any()}
  def regenerate_all_keys(opts \\ []) do
    Api.request(:put, "/api/hosts/keys", opts)
  end

  @doc """
  Triggers a config sync on a specific host (forces netclient pull).

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec sync(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def sync(host_id, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/sync", opts)
  end

  @doc """
  Triggers a config sync on all hosts.
  """
  @spec sync_all(keyword()) :: {:ok, any()} | {:error, any()}
  def sync_all(opts \\ []) do
    Api.request(:post, "/api/hosts/sync", opts)
  end

  @doc """
  Upgrades netclient on a specific host.

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec upgrade(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def upgrade(host_id, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/upgrade", opts)
  end

  @doc """
  Upgrades netclient on all hosts.
  """
  @spec upgrade_all(keyword()) :: {:ok, any()} | {:error, any()}
  def upgrade_all(opts \\ []) do
    Api.request(:post, "/api/hosts/upgrade", opts)
  end
end
