defmodule Nexmaker.Api.Hosts do
  @moduledoc """
  Host management for Netmaker API.

  Hosts represent physical or virtual machines in Netmaker. A single host
  can have multiple nodes (one per network).

  ## Host vs Node
  - **Host** = Physical/virtual machine (registered once, persists across networks)
  - **Node** = Host's membership in a specific network (one node per network)

  ## Examples

      # List all hosts
      {:ok, hosts} = Nexmaker.Api.Hosts.list()

      # Get a specific host
      {:ok, host} = Nexmaker.Api.Hosts.get(host_id)

      # Add host to a network
      {:ok, node} = Nexmaker.Api.Hosts.add_to_network(host_id, "cluster-abc")

      # Remove host from a network (delete node)
      {:ok, _} = Nexmaker.Api.Hosts.remove_from_network(host_id, "cluster-abc")

      # Delete host entirely
      {:ok, _} = Nexmaker.Api.Hosts.delete(host_id)
  """

  alias Nexmaker.Api

  @doc """
  Lists all hosts.

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, hosts}` - List of host maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, hosts} = Nexmaker.Api.Hosts.list()
  """
  @spec list(keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(opts \\ []) do
    Api.request(:get, "/api/hosts", opts)
  end

  @doc """
  Gets a specific host by ID.

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, host}` - Host map (includes `lastcheckin` timestamp)
    - `{:error, :not_found}` - Host not found
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, host} = Nexmaker.Api.Hosts.get("uuid-abc-123")
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(host_id, opts \\ []) do
    Api.request(:get, "/api/hosts/#{host_id}", opts)
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

  ## Examples

      {:ok, host} = Nexmaker.Api.Hosts.update(host_id, %{
        name: "new-hostname"
      })
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
    - `:force` - Boolean - Force delete host even if it has associated nodes (default: true)
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, response}` - Host deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      # Force delete (default - cascades to all nodes)
      {:ok, _} = Nexmaker.Api.Hosts.delete(host_id)

      # Force delete (explicit)
      {:ok, _} = Nexmaker.Api.Hosts.delete(host_id, force: true)

      # Non-force delete (will fail if host has nodes)
      {:ok, _} = Nexmaker.Api.Hosts.delete(host_id, force: false)
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(host_id, opts \\ []) do
    # Extract force option (default true for our use case - we want cascade delete)
    {force, api_opts} = Keyword.pop(opts, :force, true)

    # Add force query parameter to URL
    url = "/api/hosts/#{host_id}?force=#{force}"

    Api.request(:delete, url, api_opts)
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

  ## Examples

      {:ok, node} = Nexmaker.Api.Hosts.add_to_network(host_id, "cluster-abc")
  """
  @spec add_to_network(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def add_to_network(host_id, network_name, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/networks/#{network_name}", opts)
  end

  @doc """
  Removes a host from a network (deletes the node).

  Uses force delete by default to avoid PendingDelete limbo state.

  ## Parameters
    - host_id: String - Host UUID
    - network_name: String - Network name to leave
    - opts: Keyword - API options (base_url, master_key, force)

  ## Options
    - `:force` - Boolean, when true performs immediate hard delete without PendingDelete state (default: true)

  ## Returns
    - `{:ok, response}` - Node deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Hosts.remove_from_network(host_id, "old-cluster")
      {:ok, _} = Nexmaker.Api.Hosts.remove_from_network(host_id, "old-cluster", force: false)
  """
  @spec remove_from_network(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def remove_from_network(host_id, network_name, opts \\ []) do
    {force, api_opts} = Keyword.pop(opts, :force, true)

    query_params = if force, do: "?force=true", else: ""

    Api.request(:delete, "/api/hosts/#{host_id}/networks/#{network_name}#{query_params}", api_opts)
  end

  @doc """
  Regenerates keys for a host.

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, host}` - Host with new keys
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, host} = Nexmaker.Api.Hosts.regenerate_keys(host_id)
  """
  @spec regenerate_keys(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def regenerate_keys(host_id, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/keys", opts)
  end

  @doc """
  Syncs a host (triggers config pull).

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Sync triggered
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Hosts.sync(host_id)
  """
  @spec sync(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def sync(host_id, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/sync", opts)
  end

  @doc """
  Upgrades a host to latest netclient version.

  ## Parameters
    - host_id: String - Host UUID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Upgrade triggered
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Hosts.upgrade(host_id)
  """
  @spec upgrade(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def upgrade(host_id, opts \\ []) do
    Api.request(:post, "/api/hosts/#{host_id}/upgrade", opts)
  end

  @doc """
  Upgrades all hosts to latest netclient version.

  Triggers netclient upgrade on all registered hosts.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Upgrade triggered for all hosts
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Hosts.upgrade_all()
  """
  @spec upgrade_all(keyword()) :: {:ok, any()} | {:error, any()}
  def upgrade_all(opts \\ []) do
    Api.request(:post, "/api/hosts/upgrade", opts)
  end

  @doc """
  Syncs all hosts (triggers config pull on all hosts).

  Sends sync command to all registered hosts, forcing them to pull
  latest configuration from Netmaker server.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Sync triggered for all hosts
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Hosts.sync_all()
  """
  @spec sync_all(keyword()) :: {:ok, any()} | {:error, any()}
  def sync_all(opts \\ []) do
    Api.request(:post, "/api/hosts/sync", opts)
  end

  @doc """
  Regenerates keys for all hosts.

  Triggers key regeneration for all registered hosts.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Key regeneration triggered for all hosts
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Hosts.regenerate_all_keys()
  """
  @spec regenerate_all_keys(keyword()) :: {:ok, any()} | {:error, any()}
  def regenerate_all_keys(opts \\ []) do
    Api.request(:put, "/api/hosts/keys", opts)
  end
end
