# edge_admin/test/edge_admin/nodes/forms/change_node_cluster_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.ChangeNodeClusterFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.ChangeNodeClusterForm

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  describe "changeset/1 — valid cases" do
    test "valid cluster name returns a normalized map" do
      assert {:ok, %{"cluster_name" => "prod"}} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "prod"})
    end

    test "name with hyphens succeeds" do
      assert {:ok, %{"cluster_name" => "my-cluster"}} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "my-cluster"})
    end

    test "name with digits succeeds" do
      assert {:ok, %{"cluster_name" => "cluster01"}} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "cluster01"})
    end

    test "24-character name is valid (max length boundary)" do
      name = String.duplicate("a", 24)

      assert {:ok, %{"cluster_name" => ^name}} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => name})
    end
  end

  describe "changeset/1 — cluster_name format validation" do
    test "missing cluster_name is rejected" do
      assert {:error, changeset} = ChangeNodeClusterForm.changeset(%{})
      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "uppercase letters are rejected" do
      assert {:error, changeset} = ChangeNodeClusterForm.changeset(%{"cluster_name" => "Prod"})
      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "leading hyphen is rejected" do
      assert {:error, changeset} = ChangeNodeClusterForm.changeset(%{"cluster_name" => "-prod"})
      assert %{cluster_name: [msg]} = errors_on(changeset)
      assert msg =~ "hyphen"
    end

    test "trailing hyphen is rejected" do
      assert {:error, changeset} = ChangeNodeClusterForm.changeset(%{"cluster_name" => "prod-"})
      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "25-character name exceeds max length" do
      name = String.duplicate("a", 25)

      assert {:error, changeset} = ChangeNodeClusterForm.changeset(%{"cluster_name" => name})
      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "underscore is rejected" do
      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "my_cluster"})

      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end
  end

  describe "changeset/1 — invalid params" do
    test "non-map params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = ChangeNodeClusterForm.changeset("bad")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "nil params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = ChangeNodeClusterForm.changeset(nil)
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
