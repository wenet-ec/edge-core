# edge_admin/test/support/fixtures/nodes_fixtures.ex
defmodule EdgeAdmin.NodesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAdmin.Nodes` context.
  """

  @doc """
  Generate a proper UUID format with dashes.
  """
  def unique_node_id do
    Ecto.UUID.generate()
  end

  @doc """
  Generate a node.
  """
  def node_fixture(attrs \\ %{}) do
    default_attrs = %{
      id: unique_node_id(),
      id_type: "machine_id",
      status: "online",
      vpn_ip: "100.64.0.1",
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
end
