# edge_admin/test/edge_admin/nodes/forms/update_cluster_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.UpdateClusterFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.UpdateClusterForm

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "valid node_limit succeeds" do
      assert {:ok, result} = UpdateClusterForm.changeset(%{"node_limit" => 10})
      assert result["node_limit"] == 10
    end

    test "node_limit of 1 is accepted (minimum allowed)" do
      assert {:ok, result} = UpdateClusterForm.changeset(%{"node_limit" => 1})
      assert result["node_limit"] == 1
    end

    test "empty attrs succeeds (no fields to update)" do
      assert {:ok, result} = UpdateClusterForm.changeset(%{})
      assert result == %{}
    end

    test "wrapped cluster params are unwrapped" do
      assert {:ok, result} = UpdateClusterForm.changeset(%{"cluster" => %{"node_limit" => 5}})
      assert result["node_limit"] == 5
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — node_limit validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — node_limit validation" do
    test "node_limit of 0 is rejected" do
      assert {:error, changeset} = UpdateClusterForm.changeset(%{"node_limit" => 0})
      assert %{node_limit: [_msg]} = errors_on(changeset)
    end

    test "negative node_limit is rejected" do
      assert {:error, changeset} = UpdateClusterForm.changeset(%{"node_limit" => -5})
      assert %{node_limit: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — null vs omitted node_limit (explicit null = unset)
  # ---------------------------------------------------------------------------

  describe "changeset/1 — null vs omitted semantics" do
    test "explicit null node_limit is included in result (unsets the limit)" do
      assert {:ok, result} = UpdateClusterForm.changeset(%{"node_limit" => nil})
      assert Map.has_key?(result, "node_limit")
      assert result["node_limit"] == nil
    end

    test "omitted node_limit is excluded from result (no change)" do
      assert {:ok, result} = UpdateClusterForm.changeset(%{})
      refute Map.has_key?(result, "node_limit")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        UpdateClusterForm.changeset("not_a_map")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        UpdateClusterForm.changeset(nil)
      end
    end
  end
end
