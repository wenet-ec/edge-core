# edge_admin/test/edge_admin/nodes/views/enrollment_key_view_test.exs
defmodule EdgeAdmin.Nodes.Views.EnrollmentKeyViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Views.EnrollmentKeyView

  defp key_fixture(overrides \\ %{}) do
    cluster = %Cluster{id: "cluster-uuid-1", name: "prod"}
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %EnrollmentKey{
      id: "key-uuid-1",
      name: "default-key",
      key: "base64encodedblob",
      uses_remaining: 1,
      expires_at: nil,
      last_used_at: nil,
      cluster_id: cluster.id,
      cluster: cluster,
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      key = key_fixture()

      result = EnrollmentKeyView.render(key)

      assert result.id == key.id
      assert result.cluster_name == "prod"
      assert result.name == "default-key"
      assert result.key == "base64encodedblob"
      assert result.uses_remaining == 1
      assert result.expires_at == nil
      assert result.last_used_at == nil
      assert result.inserted_at == key.inserted_at
      assert result.updated_at == key.updated_at
    end

    test "preserves nullable fields as nil (no coercion to defaults)" do
      key = key_fixture(%{name: nil, expires_at: nil, last_used_at: nil, uses_remaining: nil})

      result = EnrollmentKeyView.render(key)

      assert result.name == nil
      assert result.uses_remaining == nil
      assert result.expires_at == nil
      assert result.last_used_at == nil
    end

    test "passes through populated timestamps" do
      now = ~U[2025-01-15 12:34:56Z]

      key = key_fixture(%{expires_at: now, last_used_at: now})

      result = EnrollmentKeyView.render(key)

      assert result.expires_at == now
      assert result.last_used_at == now
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = EnrollmentKeyView.render(key_fixture())

      expected_keys =
        Enum.sort(~w(id cluster_name name key uses_remaining expires_at last_used_at inserted_at updated_at)a)

      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
