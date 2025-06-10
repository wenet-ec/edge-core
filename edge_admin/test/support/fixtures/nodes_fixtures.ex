# edge_admin/test/support/fixtures/nodes_fixtures.ex
defmodule EdgeAdmin.NodesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAdmin.Nodes` context.
  """

  @doc """
  Generate a unique node hardware_id.
  """
  def unique_node_hardware_id, do: "hardware-id-#{System.unique_integer([:positive])}"

  @doc """
  Generate a node.
  """
  def node_fixture(attrs \\ %{}) do
    {:ok, node} =
      attrs
      |> Enum.into(%{
        hardware_id: unique_node_hardware_id(),
        # Optional fields with sensible defaults
        last_seen_at: ~U[2025-06-08 08:12:00Z],
        status: "online",
        vpn_ip: "100.64.0.#{:rand.uniform(253) + 1}"
      })
      |> EdgeAdmin.Nodes.create_node()

    node
  end

  @doc """
  Generate a minimal node with only required fields.
  """
  def minimal_node_fixture(attrs \\ %{}) do
    {:ok, node} =
      attrs
      |> Enum.into(%{
        hardware_id: unique_node_hardware_id()
      })
      |> EdgeAdmin.Nodes.create_node()

    node
  end
end
