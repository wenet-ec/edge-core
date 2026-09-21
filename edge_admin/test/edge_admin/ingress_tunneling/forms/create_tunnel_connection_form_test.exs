# edge_admin/test/edge_admin/ingress_tunneling/forms/create_tunnel_connection_form_test.exs
defmodule EdgeAdmin.IngressTunneling.Forms.CreateTunnelConnectionFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.IngressTunneling.Forms.CreateTunnelConnectionForm

  test "requires a valid node UUID" do
    node_id = Ecto.UUID.generate()
    assert {:ok, %{"node_id" => ^node_id}} = CreateTunnelConnectionForm.changeset(%{"node_id" => node_id})
  end

  test "rejects a missing node id" do
    assert {:error, changeset} = CreateTunnelConnectionForm.changeset(%{})
    assert %{node_id: [_]} = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end

  test "rejects a malformed node UUID" do
    assert {:error, changeset} = CreateTunnelConnectionForm.changeset(%{"node_id" => "not-a-uuid"})
    assert %{node_id: [_]} = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end
end
