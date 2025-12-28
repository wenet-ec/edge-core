# edge_admin/test/support/fixtures/nodes_fixtures.ex
defmodule EdgeAdmin.NodesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAdmin.Nodes` context.
  """

  import Mox

  @doc """
  Generate a proper UUID format with dashes.
  """
  def unique_node_id do
    Ecto.UUID.generate()
  end

  @doc """
  Generate a cluster with mocked Nexmaker API calls.
  """
  def cluster_fixture(attrs \\ %{}) do
    # Mock the Nexmaker network creation
    expect(NexmakerMock, :create_network, fn _network_name, _params ->
      {:ok, %{}}
    end)

    default_attrs = %{
      ipv4_range: "100.64.#{:rand.uniform(255)}.0/24"
    }

    {:ok, cluster} =
      default_attrs
      |> Map.merge(attrs)
      |> EdgeAdmin.Nodes.create_cluster()

    cluster
  end

  @doc """
  Generate a node.
  """
  def node_fixture(attrs \\ %{}) do
    default_attrs = %{
      id: unique_node_id(),
      cluster_id: unique_node_id(),
      id_type: "persistent",
      status: "online",
      http_port: 44_000,
      ssh_port: 42_222,
      metrics_port: 49_100,
      http_proxy_port: 44_880,
      socks5_proxy_port: 44_180,
      last_seen_at: ~U[2025-06-08 08:12:00Z]
    }

    {:ok, node} =
      default_attrs
      |> Map.merge(attrs)
      |> EdgeAdmin.Nodes.create_node()

    node
  end

  @doc """
  Generate a ssh_username.
  """
  def ssh_username_fixture(attrs \\ %{}) do
    # Create a node first since ssh_username requires node_id
    node = node_fixture()

    {:ok, ssh_username} =
      attrs
      |> Enum.into(%{
        username: "some username",
        node_id: node.id
      })
      |> EdgeAdmin.Nodes.create_ssh_username()

    ssh_username
  end

  @doc """
  Generate a ssh_public_key.
  """
  def ssh_public_key_fixture(attrs \\ %{}) do
    ssh_username = ssh_username_fixture()

    # Use a REAL valid Ed25519 key (this is a test key, not sensitive)
    valid_ed25519_key =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 test@example.com"

    {:ok, ssh_public_key} =
      attrs
      |> Enum.into(%{
        key_name: "some key_name",
        public_key: valid_ed25519_key,
        ssh_username_id: ssh_username.id
      })
      |> EdgeAdmin.Nodes.create_ssh_public_key()

    ssh_public_key
  end
end
