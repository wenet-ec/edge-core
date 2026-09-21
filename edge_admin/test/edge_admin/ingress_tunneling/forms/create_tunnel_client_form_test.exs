# edge_admin/test/edge_admin/ingress_tunneling/forms/create_tunnel_client_form_test.exs
defmodule EdgeAdmin.IngressTunneling.Forms.CreateTunnelClientFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.Forms.CreateTunnelClientForm

  test "defaults node_ids to an empty list" do
    assert {:ok, %{"node_ids" => []}} = CreateTunnelClientForm.changeset(%{})
  end

  test "accepts unique node UUIDs" do
    node_id = Ecto.UUID.generate()
    assert {:ok, %{"node_ids" => [^node_id]}} = CreateTunnelClientForm.changeset(%{"node_ids" => [node_id]})
  end

  test "rejects duplicate node UUIDs" do
    node_id = Ecto.UUID.generate()
    assert {:error, changeset} = CreateTunnelClientForm.changeset(%{"node_ids" => [node_id, node_id]})
    assert %{node_ids: [_]} = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end

  test "rejects malformed node UUIDs" do
    assert {:error, changeset} = CreateTunnelClientForm.changeset(%{"node_ids" => ["not-a-uuid"]})
    assert %{node_ids: [_]} = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end
end
