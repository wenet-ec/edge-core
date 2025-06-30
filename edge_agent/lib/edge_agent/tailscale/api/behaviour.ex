# edge_admin/lib/edge_admin/tailscale/api/behaviour.ex
defmodule EdgeAgent.Tailscale.Api.Behaviour do
  @moduledoc """
  Behaviour for Tailscale API operations via Headscale.

  This behaviour defines the interface for Headscale API operations
  such as node management, enrollment key creation, and user management.
  It enables easy mocking during tests and abstraction of the API implementation.
  """

  @type node_result :: {:ok, map()} | {:error, atom() | tuple()}
  @type nodes_result :: {:ok, [map()]} | {:error, atom() | tuple()}
  @type enrollment_key_result :: {:ok, map()} | {:error, atom() | tuple()}
  @type user_result :: {:ok, map()} | {:error, atom() | tuple()}

  @doc """
  Gets node information by VPN hostname.

  Returns node details including VPN IP, hostname, online status, and last seen time.
  """
  @callback get_node_by_hostname(String.t()) :: node_result()

  @doc """
  Lists all nodes for a specific user.

  Returns a list of nodes with their connection details and status.
  """
  @callback list_nodes_for_user(String.t()) :: nodes_result()

  @doc """
  Creates a new enrollment key for the specified user.

  Returns enrollment key details including the key string, expiration, and creation time.
  """
  @callback create_enrollment_key(String.t()) :: enrollment_key_result()

  @doc """
  Gets user information by username.

  Returns user details including ID and name.
  """
  @callback get_user(String.t()) :: user_result()
end
