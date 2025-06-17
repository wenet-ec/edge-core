# edge_admin/lib/edge_admin/headscale.ex
defmodule EdgeAdmin.Headscale do
  @moduledoc """
  The Headscale context for managing VPN node information and enrollment.

  This context provides functionality for interacting with the Headscale
  VPN service to retrieve node information, create enrollment keys, and
  manage VPN users.
  """

  @doc """
  Gets node information by VPN hostname.

  ## Examples

      iex> get_node_by_hostname("node-abc123")
      {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "node-abc123", online: true}}

      iex> get_node_by_hostname("nonexistent")
      {:error, :node_not_found}

  """
  def get_node_by_hostname(vpn_hostname) do
    client().get_node_by_hostname(vpn_hostname)
  end

  @doc """
  Lists all nodes for a specific user.

  ## Examples

      iex> list_nodes_for_user("edge-nodes")
      {:ok, [%{vpn_ip: "100.64.0.1", vpn_hostname: "node-abc123"}]}

  """
  def list_nodes_for_user(user \\ "edge-nodes") do
    client().list_nodes_for_user(user)
  end

  @doc """
  Creates a new enrollment key for edge nodes to join the VPN.

  ## Examples

      iex> create_enrollment_key()
      {:ok, %{key: "preauth-key-abc123", expiration: "2024-06-10T15:30:00Z", created_at: "2024-06-10T14:30:00Z"}}

      iex> create_enrollment_key()
      {:error, :vpn_service_unavailable}

  """
  def create_enrollment_key(user \\ "edge-nodes") do
    client().create_enrollment_key(user)
  end

  @doc """
  Gets user information by username.

  ## Examples

      iex> get_user("edge-nodes")
      {:ok, %{id: "user123", name: "edge-nodes"}}

      iex> get_user("nonexistent")
      {:error, :user_not_found}

  """
  def get_user(username) do
    client().get_user(username)
  end

  # Private function to get the configured client module
  defp client do
    Application.get_env(:edge_admin, :headscale_client, EdgeAdmin.Headscale.Client)
  end
end
