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
end
