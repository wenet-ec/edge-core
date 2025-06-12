# edge_admin/test/support/fixtures/nodes_fixtures.ex
defmodule EdgeAdmin.NodesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAdmin.Nodes` context.
  """

  @doc """
  Generate a unique hardware ID in hex format (like real hardware IDs).
  """
  def unique_hardware_id do
    # Generate a 32-character hex string like real machine IDs
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generate a node.
  """
  def node_fixture(attrs \\ %{}) do
    {:ok, node} =
      attrs
      |> Enum.into(%{
        id: Map.get(attrs, :id, unique_hardware_id()),
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
        id: Map.get(attrs, :id, unique_hardware_id())
      })
      |> EdgeAdmin.Nodes.create_node()

    node
  end
end
