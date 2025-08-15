# tailscale/lib/tailscale/behaviours/api.ex
defmodule Tailscale.Behaviours.Api do
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

  @callback get_node_by_hostname(String.t()) :: node_result()
  @callback list_nodes_for_user(String.t()) :: nodes_result()
  @callback create_enrollment_key(String.t()) :: enrollment_key_result()
  @callback get_user(String.t()) :: user_result()
end