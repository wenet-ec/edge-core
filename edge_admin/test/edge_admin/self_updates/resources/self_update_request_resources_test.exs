# edge_admin/test/edge_admin/self_updates/resources/self_update_request_resources_test.exs
defmodule EdgeAdmin.SelfUpdates.Resources.SelfUpdateRequestResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.SelfUpdates.Resources.SelfUpdateRequestResources
  alias EdgeAdmin.Test.Fixtures

  defp insert_request!(inserted_at, targeting, status \\ :pending) do
    Fixtures.insert_self_update_request!(%{
      targeting: targeting,
      status: status,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  test "returns no match when there are no self-update requests" do
    node = %Node{id: Ecto.UUID.generate()}

    assert {:ok, %{including_me: false, inserted_at: nil}} =
             SelfUpdateRequestResources.latest_for_node(node, fn _targeting -> [] end)
  end

  test "checks the latest request and returns its timestamp" do
    node = %Node{id: Ecto.UUID.generate()}
    inserted_at = ~U[2026-02-01 12:00:00Z]
    insert_request!(inserted_at, %{"type" => "nodes", "node_ids" => [node.id]})

    assert {:ok, %{including_me: true, inserted_at: ^inserted_at}} =
             SelfUpdateRequestResources.latest_for_node(node, fn _targeting -> [node] end)
  end

  test "uses only the newest request when determining inclusion" do
    node = %Node{id: Ecto.UUID.generate()}
    older = ~U[2026-02-01 12:00:00Z]
    newer = ~U[2026-02-02 12:00:00Z]

    insert_request!(older, %{"type" => "nodes", "node_ids" => [node.id]})
    insert_request!(newer, %{"type" => "nodes", "node_ids" => [Ecto.UUID.generate()]})

    assert {:ok, %{including_me: false, inserted_at: ^newer}} =
             SelfUpdateRequestResources.latest_for_node(node, fn targeting ->
               if node.id in targeting["node_ids"], do: [node], else: []
             end)
  end
end
