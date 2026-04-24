# nexmaker/lib/nexmaker/api/dns.ex
defmodule Nexmaker.Api.DNS do
  @moduledoc """
  DNS management for Netmaker API.

  Two distinct concepts:

  1. **DNS entries** — hostname → IP mappings scoped to a network.
     Netmaker auto-creates entries for every node; custom entries can be added.

  2. **Nameservers** — upstream DNS server configurations. Pushed to each
     host in the `DnsNameservers` field of HostPeerUpdate/HostPull payloads;
     netclient installs them into its own local DNS listener, per-network
     or globally. New in v1.5.1 (replaces the prior CoreDNS-backed setup).

  ## DNS entry shape

      %{
        "name" => "gateway.cluster-abc.nm.internal",
        "address" => "100.64.0.2",
        "network" => "cluster-abc"
      }

  ## Nameserver shape

      %{
        "id" => "uuid",
        "name" => "my-nameserver",
        "network_id" => "cluster-abc",
        "description" => "",
        "default" => false,
        "fallback" => false,
        "servers" => ["8.8.8.8", "1.1.1.1"],
        "match_all" => false,
        "domains" => [%{"domain" => "example.com", "wildcard" => true}],
        "tags" => {},
        "nodes" => {},
        "status" => true,
        "created_by" => "admin"
      }
  """

  alias Nexmaker.Api

  # ---------------------------------------------------------------------------
  # DNS Entries
  # ---------------------------------------------------------------------------

  @doc """
  Gets all DNS entries across all networks.

  ## Returns
    - `{:ok, entries}` - List of all DNS entry maps (empty list if none)
    - `{:error, reason}` - Error occurred
  """
  @spec get_all(keyword()) :: {:ok, [map()]} | {:error, any()}
  def get_all(opts \\ []) do
    case Api.request(:get, "/api/dns", opts) do
      {:ok, nil} -> {:ok, []}
      {:ok, %{body: b}} when b in [nil, ""] -> {:ok, []}
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists DNS entries for a specific network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, entries}` - List of DNS entry maps
    - `{:error, reason}` - Error occurred
  """
  @spec list(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(network_name, opts \\ []) do
    case Api.request(:get, "/api/dns/adm/#{network_name}", opts) do
      {:ok, nil} -> {:ok, []}
      {:ok, %{body: b}} when b in [nil, ""] -> {:ok, []}
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      other -> other
    end
  end

  @doc """
  Gets auto-generated node DNS entries for a network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec list_node_entries(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_node_entries(network_name, opts \\ []) do
    case Api.request(:get, "/api/dns/adm/#{network_name}/nodes", opts) do
      {:ok, nil} -> {:ok, []}
      {:ok, %{body: b}} when b in [nil, ""] -> {:ok, []}
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      other -> other
    end
  end

  @doc """
  Gets custom DNS entries for a network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec list_custom_entries(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_custom_entries(network_name, opts \\ []) do
    case Api.request(:get, "/api/dns/adm/#{network_name}/custom", opts) do
      {:ok, nil} ->
        {:ok, []}

      {:ok, %{body: b}} when b in [nil, ""] ->
        {:ok, []}

      {:ok, entries} when is_list(entries) ->
        {:ok, entries}

      # Netmaker returns 500 "could not find any records" for empty custom entries
      {:error, {:http_error, 500, %{"Message" => msg}}} when is_binary(msg) ->
        if String.contains?(msg, "could not find any records"),
          do: {:ok, []},
          else: {:error, {:http_error, 500, %{"Message" => msg}}}

      other ->
        other
    end
  end

  @doc """
  Creates a custom DNS entry.

  ## Parameters
    - network_name: String - Network name
    - attrs: Map - DNS entry attributes:
      - `:name` - Hostname (e.g., "gateway.cluster-abc.nm.internal")
      - `:address` - IP address (e.g., "100.64.0.2")
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, entry}` - Created DNS entry map
    - `{:error, reason}` - Error occurred
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
    - dns_name: String - Hostname to delete
    - opts: Keyword - API options (base_url, master_key)
  """
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, dns_name, opts \\ []) do
    Api.request(:delete, "/api/dns/#{network_name}/#{dns_name}", opts)
  end

  @doc """
  Pushes DNS changes to all nodes across all networks.

  ## Notes

  Returns `{:error, {:bad_request, body}}` if DNS mode is disabled on the server
  (`MANAGE_DNS=false`). This is a deployment config condition, not a data error.
  """
  @spec push(keyword()) :: {:ok, any()} | {:error, any()}
  def push(opts \\ []) do
    Api.request(:post, "/api/dns/adm/pushdns", opts)
  end

  @doc """
  Syncs DNS for a network.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Notes

  Returns `{:error, {:bad_request, body}}` if manage DNS is disabled on the server.
  """
  @spec sync(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def sync(network_name, opts \\ []) do
    Api.request(:post, "/api/dns/adm/#{network_name}/sync", opts)
  end

  # ---------------------------------------------------------------------------
  # Nameservers (v1.5.1)
  # ---------------------------------------------------------------------------

  @doc """
  Lists nameservers configured for a network.

  ## Parameters
    - network_name: String - Network name (required — Netmaker returns 400 without it)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, nameservers}` - List of nameserver maps
    - `{:error, reason}` - Error occurred
  """
  @spec list_nameservers(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_nameservers(network_name, opts \\ []) do
    case Api.request(:get, "/api/v1/nameserver", Keyword.put(opts, :query, network: network_name)) do
      {:ok, %{"Response" => nameservers}} -> {:ok, nameservers}
      other -> other
    end
  end

  @doc """
  Gets the global nameserver list (built-in, non-configurable).

  Returns the pre-defined global nameservers available for reference.

  ## Returns
    - `{:ok, nameservers}` - Map of name => nameserver
    - `{:error, reason}` - Error occurred
  """
  @spec get_global_nameservers(keyword()) :: {:ok, map()} | {:error, any()}
  def get_global_nameservers(opts \\ []) do
    case Api.request(:get, "/api/v1/nameserver/global", opts) do
      {:ok, %{"Response" => nameservers}} -> {:ok, nameservers}
      other -> other
    end
  end

  @doc """
  Creates a nameserver configuration.

  ## Parameters
    - attrs: Map - Nameserver attributes:
      - `:name` - Nameserver name (required)
      - `:network_id` - Network name (required)
      - `:servers` - List of upstream DNS server IPs (required)
      - `:match_all` - Boolean - match all domains (default: false)
      - `:domains` - List of domain maps `[%{domain: "example.com", wildcard: true}]`
      - `:fallback` - Boolean - use as fallback only (default: false)
      - `:description` - Optional description
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, nameserver}` - Created nameserver map
    - `{:error, reason}` - Error occurred
  """
  @spec create_nameserver(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create_nameserver(attrs, opts \\ []) do
    case Api.request(:post, "/api/v1/nameserver", Keyword.put(opts, :body, attrs)) do
      {:ok, %{"Response" => nameserver}} -> {:ok, nameserver}
      other -> other
    end
  end

  @doc """
  Updates a nameserver configuration.

  ## Parameters
    - attrs: Map - Nameserver attributes including `:id`
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, nameserver}` - Updated nameserver map
    - `{:error, {:bad_request, body}}` - Nameserver not found, validation failure, or AD domain
      on fallback nameserver (Netmaker uses 400, not 404, for not-found on update)
    - `{:error, reason}` - Other error
  """
  @spec update_nameserver(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update_nameserver(attrs, opts \\ []) do
    case Api.request(:put, "/api/v1/nameserver", Keyword.put(opts, :body, attrs)) do
      {:ok, %{"Response" => nameserver}} -> {:ok, nameserver}
      other -> other
    end
  end

  @doc """
  Deletes a nameserver configuration.

  ## Parameters
    - nameserver_id: String - Nameserver ID
    - opts: Keyword - API options (base_url, master_key)

  ## Notes

  Returns `{:error, {:bad_request, body}}` (not `{:error, :not_found}`) when:
  - The nameserver ID does not exist
  - Attempting to delete a default nameserver (protected)
  """
  @spec delete_nameserver(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete_nameserver(nameserver_id, opts \\ []) do
    Api.request(:delete, "/api/v1/nameserver", Keyword.put(opts, :query, id: nameserver_id))
  end
end
