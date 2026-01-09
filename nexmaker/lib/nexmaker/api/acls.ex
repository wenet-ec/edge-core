defmodule Nexmaker.Api.ACLs do
  @moduledoc """
  Network ACL management for Netmaker API.

  Network ACLs control node-to-node traffic within a network. This is different
  from user ACL policies (Pro feature) - network ACLs are firewall rules between nodes.

  ## Use Cases

  - Allow/deny traffic between specific nodes
  - Create network segmentation within a VPN network
  - Default deny-all with explicit allow rules

  ## Examples

      # Get current ACLs for a network
      {:ok, acls} = Nexmaker.Api.ACLs.get("admin-cluster")

      # Update ACLs (node-to-node rules)
      {:ok, acls} = Nexmaker.Api.ACLs.update("admin-cluster", %{
        "node-a-id" => %{"node-b-id" => 1, "node-c-id" => 2}
      })

      # Update ACLs v2 (includes external clients)
      {:ok, acls} = Nexmaker.Api.ACLs.update_v2("admin-cluster", acl_container)
  """

  alias Nexmaker.Api

  @doc """
  Gets network ACL container (node-to-node traffic rules).

  Returns the ACL container for a network, which maps node IDs to allowed peers.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, acls}` - ACL container map (node_id => %{peer_id => access_level})
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, acls} = Nexmaker.Api.ACLs.get("cluster-abc")
      # Returns: %{"node-a-id" => %{"node-b-id" => 1, "node-c-id" => 2}}
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(network_name, opts \\ []) do
    Api.request(:get, "/api/networks/#{network_name}/acls", opts)
  end

  @doc """
  Updates network ACL (node-to-node firewall rules).

  Sets the ACL container for a network. The container maps node IDs to their
  allowed peers with access levels.

  ## Parameters
    - network_name: String - Network name
    - acl_container: Map - ACL rules (node_id => %{peer_id => access_level})
    - opts: Keyword - API options (base_url, master_key)

  ## Access Levels
    - 0: No access (deny)
    - 1: Node access (allow)
    - 2: Full access (admin/unrestricted)

  ## Returns
    - `{:ok, acls}` - Updated ACL container
    - `{:error, reason}` - Error occurred

  ## Examples

      # Allow node-a to communicate with node-b and node-c
      {:ok, acls} = Nexmaker.Api.ACLs.update("cluster-abc", %{
        "node-a-id" => %{
          "node-b-id" => 1,
          "node-c-id" => 1
        }
      })
  """
  @spec update(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(network_name, acl_container, opts \\ []) do
    Api.request(:put, "/api/networks/#{network_name}/acls", Keyword.put(opts, :body, acl_container))
  end

  @doc """
  Updates network ACL v2 (includes external clients support).

  Enhanced ACL endpoint that supports external clients in addition to nodes.

  ## Parameters
    - network_name: String - Network name
    - acl_container: Map - ACL rules including external clients
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, acls}` - Updated ACL container
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, acls} = Nexmaker.Api.ACLs.update_v2("cluster-abc", acl_container)
  """
  @spec update_v2(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update_v2(network_name, acl_container, opts \\ []) do
    Api.request(:put, "/api/networks/#{network_name}/acls/v2", Keyword.put(opts, :body, acl_container))
  end
end
