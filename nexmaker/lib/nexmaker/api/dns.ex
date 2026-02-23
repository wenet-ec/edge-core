defmodule Nexmaker.Api.DNS do
  @moduledoc """
  DNS management for Netmaker API.

  Netmaker provides built-in DNS for networks. Each network gets automatic
  DNS entries for nodes, and you can create custom DNS records.

  ## Automatic DNS

  Netmaker automatically creates DNS entries for nodes:
  - Pattern: `{hostname}.{network}.nm.internal`
  - Example: `admin-uuid-123.admin-cluster.nm.internal`

  ## Custom DNS

  You can create additional custom DNS entries for any hostname pattern.

  ## Examples

      # Create a custom DNS entry
      {:ok, dns} = Nexmaker.Api.DNS.create("admin-cluster", %{
        name: "admin-a.admin-cluster.nm.internal",
        address: "10.100.0.5"
      })

      # List all DNS entries for a network
      {:ok, entries} = Nexmaker.Api.DNS.list("admin-cluster")

      # Delete a custom DNS entry
      {:ok, _} = Nexmaker.Api.DNS.delete("admin-cluster", "admin-a.admin-cluster.nm.internal")
  """

  alias Nexmaker.Api

  @doc """
  Gets all DNS entries across all networks.

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key

  ## Returns
    - `{:ok, dns_entries}` - List of all DNS entry maps (empty list if no DNS entries exist)
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, entries} = Nexmaker.Api.DNS.get_all()
  """
  @spec get_all(keyword()) :: {:ok, [map()]} | {:error, any()}
  def get_all(opts \\ []) do
    case Api.request(:get, "/api/dns", opts) do
      {:ok, nil} ->
        # API returns null when no DNS entries exist
        {:ok, []}

      {:ok, %{body: nil}} ->
        # Req decodes empty 200 body as %{body: nil}
        {:ok, []}

      {:ok, entries} when is_list(entries) ->
        {:ok, entries}

      {:ok, other} ->
        # Unexpected response format
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists DNS entries for a specific network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, dns_entries}` - List of DNS entry maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, entries} = Nexmaker.Api.DNS.list("admin-cluster")
  """
  @spec list(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(network_name, opts \\ []) do
    case Api.request(:get, "/api/dns/adm/#{network_name}", opts) do
      {:ok, nil} -> {:ok, []}
      {:ok, %{body: nil}} -> {:ok, []}
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      other -> other
    end
  end

  @doc """
  Creates a custom DNS entry.

  ## Parameters
    - network_name: String - Network name
    - attrs: Map - DNS entry attributes:
      - `:name` - Hostname (e.g., "admin-a.admin-cluster.nm.internal")
      - `:address` - IP address (e.g., "10.100.0.5")
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, dns_entry}` - Created DNS entry map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, dns} = Nexmaker.Api.DNS.create("cluster-abc", %{
        name: "gateway.cluster-abc.nm.internal",
        address: "10.71.128.1"
      })
  """
  @spec create(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, attrs, opts \\ []) do
    body = Map.put(attrs, :network, network_name)
    Api.request(:post, "/api/dns/#{network_name}", Keyword.put(opts, :body, body))
  end

  @doc """
  Deletes a custom DNS entry.

  ## Parameters
    - network_name: String - Network name
    - dns_name: String - DNS hostname to delete
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - DNS entry deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.DNS.delete("admin-cluster",
        "admin-a.admin-cluster.nm.internal"
      )
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, dns_name, opts \\ []) do
    Api.request(:delete, "/api/dns/#{network_name}/#{dns_name}", opts)
  end

  @doc """
  Pushes DNS changes to all nodes across all networks.

  NOTE: This endpoint does NOT take a network parameter - it pushes to ALL networks.
  Use push_adm/0 for the same functionality (alternative endpoint).

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - DNS push triggered
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.DNS.push()
  """
  @spec push(keyword()) :: {:ok, any()} | {:error, any()}
  def push(opts \\ []) do
    Api.request(:post, "/api/dns/adm/pushdns", opts)
  end

  @doc """
  @deprecated "Use push/1 or push_adm/1 instead - this function signature is incorrect"
  """
  def push(_network_name, opts) when is_list(opts) do
    push(opts)
  end

  @doc """
  Syncs DNS for a network (admin endpoint).

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - DNS sync triggered
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.DNS.sync("admin-cluster")
  """
  @spec sync(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def sync(network_name, opts \\ []) do
    Api.request(:post, "/api/dns/adm/#{network_name}/sync", opts)
  end

  @doc """
  Gets DNS entries for a network (admin endpoint).

  Alternative admin-specific endpoint for retrieving network DNS entries.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, dns_entries}` - List of DNS entry maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, entries} = Nexmaker.Api.DNS.get_adm_network("admin-cluster")
  """
  @spec get_adm_network(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def get_adm_network(network_name, opts \\ []) do
    case Api.request(:get, "/api/dns/adm/#{network_name}", opts) do
      {:ok, nil} -> {:ok, []}
      {:ok, %{body: nil}} -> {:ok, []}
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      other -> other
    end
  end

  @doc """
  Gets node DNS entries for a network.

  Returns DNS entries for nodes (automatically created by Netmaker).

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, dns_entries}` - List of node DNS entry maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, node_entries} = Nexmaker.Api.DNS.get_node_entries("cluster-abc")
  """
  @spec get_node_entries(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def get_node_entries(network_name, opts \\ []) do
    Api.request(:get, "/api/dns/adm/#{network_name}/nodes", opts)
  end

  @doc """
  Gets custom DNS entries for a network.

  Returns only custom DNS entries (created via API, not auto-generated).

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, dns_entries}` - List of custom DNS entry maps
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, custom_entries} = Nexmaker.Api.DNS.get_custom_entries("cluster-abc")
  """
  @spec get_custom_entries(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def get_custom_entries(network_name, opts \\ []) do
    Api.request(:get, "/api/dns/adm/#{network_name}/custom", opts)
  end

  @doc """
  Pushes DNS updates to all nodes (admin endpoint).

  Alternative admin-specific endpoint for pushing DNS changes.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - DNS push triggered
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.DNS.push_adm()
  """
  @spec push_adm(keyword()) :: {:ok, any()} | {:error, any()}
  def push_adm(opts \\ []) do
    Api.request(:post, "/api/dns/adm/pushdns", opts)
  end

  @doc """
  Syncs DNS for a network (admin endpoint).

  Alternative admin-specific endpoint for DNS sync.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - DNS sync triggered
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.DNS.sync_adm("admin-cluster")
  """
  @spec sync_adm(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def sync_adm(network_name, opts \\ []) do
    Api.request(:post, "/api/dns/adm/#{network_name}/sync", opts)
  end
end
