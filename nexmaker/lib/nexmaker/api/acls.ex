# nexmaker/lib/nexmaker/api/acls.ex
defmodule Nexmaker.Api.ACLs do
  @moduledoc """
  ACL policy management for Netmaker API.

  ACLs define network access policies controlling which nodes/tags can communicate
  with each other, with optional protocol/port/direction constraints.

  ## Response shape (Acl)

      %{
        "id" => "uuid",
        "name" => "allow-web",
        "network_id" => "cluster-abc",
        "policy_type" => "device",        # "device" | "tag" | "user" | "egress"
        "src_type" => [
          %{"id" => "node", "name" => "node-name", "value" => "node-uuid"}
        ],
        "dst_type" => [
          %{"id" => "node", "name" => "node-name", "value" => "node-uuid"}
        ],
        "protocol" => "tcp",              # "tcp" | "udp" | "icmp" | "any"
        "type" => "",                     # service type
        "ports" => ["443", "80"],
        "allowed_traffic_direction" => 1, # 1 = bidirectional, 2 = unidirectional
        "enabled" => true,
        "default" => false,
        "meta_data" => "",
        "created_by" => "admin",
        "created_at" => "2026-01-01T00:00:00Z"
      }
  """

  alias Nexmaker.Api

  @doc """
  Lists all ACL policies for a network.

  ## Parameters
    - network_id: String - Network name/ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, acls}` - List of ACL policy maps
    - `{:error, reason}` - Error occurred
  """
  @spec list(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(network_id, opts \\ []) do
    case Api.request(:get, "/api/v1/acls?network=#{network_id}", opts) do
      {:ok, %{"Response" => acls}} -> {:ok, acls}
      other -> other
    end
  end

  @doc """
  Creates an ACL policy.

  ## Parameters
    - attrs: Map - ACL attributes:
      - `:name` - Policy name (required)
      - `:network_id` - Network name (required)
      - `:policy_type` - "device" | "tag" | "user" | "egress" (required)
      - `:src_type` - List of source tags `[%{id: type, value: id}]`
      - `:dst_type` - List of destination tags
      - `:protocol` - "tcp" | "udp" | "icmp" | "any" (default: "any")
      - `:ports` - List of port strings (e.g., ["443", "80"])
      - `:allowed_traffic_direction` - 1 = bidirectional, 2 = unidirectional
      - `:enabled` - Boolean (default: true)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, acl}` - Created ACL policy map
    - `{:error, reason}` - Error occurred
  """
  @spec create(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(attrs, opts \\ []) do
    case Api.request(:post, "/api/v1/acls", Keyword.put(opts, :body, attrs)) do
      {:ok, %{"Response" => acl}} -> {:ok, acl}
      other -> other
    end
  end

  @doc """
  Updates an ACL policy.

  ## Parameters
    - acl_id: String - ACL policy ID
    - attrs: Map - Attributes to update (same shape as create)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, acl}` - Updated ACL policy map
    - `{:error, reason}` - Error occurred
  """
  @spec update(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(acl_id, attrs, opts \\ []) do
    body = Map.put(attrs, :id, acl_id)
    case Api.request(:put, "/api/v1/acls", Keyword.put(opts, :body, body)) do
      {:ok, %{"Response" => acl}} -> {:ok, acl}
      other -> other
    end
  end

  @doc """
  Deletes an ACL policy.

  ## Parameters
    - acl_id: String - ACL policy ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - ACL deleted
    - `{:error, reason}` - Error occurred
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(acl_id, opts \\ []) do
    Api.request(:delete, "/api/v1/acls?acl_id=#{acl_id}", opts)
  end

  @doc """
  Lists ACL policies for an egress resource.

  ## Parameters
    - egress_id: String - Egress resource ID (required)
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, acls}` - List of egress ACL policy maps
    - `{:error, reason}` - Error occurred
  """
  @spec list_egress(String.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def list_egress(egress_id, opts \\ []) do
    case Api.request(:get, "/api/v1/acls/egress?egress_id=#{egress_id}", opts) do
      {:ok, %{"Response" => acls}} -> {:ok, acls}
      other -> other
    end
  end

  @doc """
  Lists available ACL policy types.

  Returns the allowed policy_type values and their tag prefixes.

  ## Returns
    - `{:ok, types}` - List of policy type maps
    - `{:error, reason}` - Error occurred
  """
  @spec policy_types(keyword()) :: {:ok, [map()]} | {:error, any()}
  def policy_types(opts \\ []) do
    case Api.request(:get, "/api/v1/acls/policy_types", opts) do
      {:ok, %{"Response" => types}} -> {:ok, types}
      other -> other
    end
  end
end
