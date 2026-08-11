# edge_admin/test/edge_admin/self_updates/resources/requests_test.exs
defmodule EdgeAdmin.SelfUpdates.Resources.RequestsTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.SelfUpdates.Resources.Requests
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  defp insert_request!(inserted_at, targeting) do
    Repo.insert!(%SelfUpdateRequest{
      id: Ecto.UUID.generate(),
      targeting: targeting,
      status: :pending,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  test "returns no match when there are no self-update requests" do
    node = %Node{id: Ecto.UUID.generate()}

    assert {:ok, %{including_me: false, inserted_at: nil}} =
             Requests.latest_for_node(node, fn _targeting -> [] end)
  end

  test "checks the latest request and returns its timestamp" do
    node = %Node{id: Ecto.UUID.generate()}
    inserted_at = ~U[2026-02-01 12:00:00Z]
    insert_request!(inserted_at, %{"type" => "nodes", "node_ids" => [node.id]})

    assert {:ok, %{including_me: true, inserted_at: ^inserted_at}} =
             Requests.latest_for_node(node, fn _targeting -> [node] end)
  end

  test "uses only the newest request when determining inclusion" do
    node = %Node{id: Ecto.UUID.generate()}
    older = ~U[2026-02-01 12:00:00Z]
    newer = ~U[2026-02-02 12:00:00Z]

    insert_request!(older, %{"type" => "nodes", "node_ids" => [node.id]})
    insert_request!(newer, %{"type" => "nodes", "node_ids" => [Ecto.UUID.generate()]})

    assert {:ok, %{including_me: false, inserted_at: ^newer}} =
             Requests.latest_for_node(node, fn targeting ->
               if node.id in targeting["node_ids"], do: [node], else: []
             end)
  end
end
