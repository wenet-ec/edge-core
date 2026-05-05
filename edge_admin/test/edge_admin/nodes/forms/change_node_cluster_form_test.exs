# edge_admin/test/edge_admin/nodes/forms/change_node_cluster_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.ChangeNodeClusterFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.ChangeNodeClusterForm

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # Stub callbacks — no DB needed
  defp cluster_found(_name), do: {:ok, %{name: "prod"}}
  defp cluster_not_found(_name), do: {:error, :not_found}

  # ---------------------------------------------------------------------------
  # changeset/2 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/2 — valid cases" do
    test "valid cluster name returns {:ok, cluster_name} string" do
      assert {:ok, "prod"} = ChangeNodeClusterForm.changeset(%{"cluster_name" => "prod"}, &cluster_found/1)
    end

    test "name with hyphens succeeds" do
      assert {:ok, "my-cluster"} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "my-cluster"}, &cluster_found/1)
    end

    test "name with digits succeeds" do
      assert {:ok, "cluster01"} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "cluster01"}, &cluster_found/1)
    end

    test "24-character name is valid (max length boundary)" do
      name = String.duplicate("a", 24)

      assert {:ok, ^name} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => name}, &cluster_found/1)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — cluster_name format validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — cluster_name format validation" do
    test "missing cluster_name is rejected" do
      assert {:error, changeset} = ChangeNodeClusterForm.changeset(%{}, &cluster_found/1)
      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "uppercase letters are rejected" do
      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "Prod"}, &cluster_found/1)

      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "leading hyphen is rejected" do
      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "-prod"}, &cluster_found/1)

      assert %{cluster_name: [msg]} = errors_on(changeset)
      assert msg =~ "hyphen"
    end

    test "trailing hyphen is rejected" do
      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "prod-"}, &cluster_found/1)

      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "25-character name exceeds max length" do
      name = String.duplicate("a", 25)

      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => name}, &cluster_found/1)

      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end

    test "underscore is rejected" do
      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(
                 %{"cluster_name" => "my_cluster"},
                 &cluster_found/1
               )

      assert %{cluster_name: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — cluster existence check
  # ---------------------------------------------------------------------------

  describe "changeset/2 — cluster existence check" do
    test "cluster not found returns error on cluster_name field" do
      assert {:error, changeset} =
               ChangeNodeClusterForm.changeset(
                 %{"cluster_name" => "missing"},
                 &cluster_not_found/1
               )

      assert %{cluster_name: [msg]} = errors_on(changeset)
      assert msg =~ "not found"
    end

    test "cluster found returns :ok" do
      assert {:ok, "prod"} =
               ChangeNodeClusterForm.changeset(%{"cluster_name" => "prod"}, &cluster_found/1)
    end

    test "cluster existence is not checked when format validation fails" do
      # If format fails, the DB callback should not be invoked
      called = :counters.new(1, [])

      counting_fn = fn _name ->
        :counters.add(called, 1, 1)
        {:ok, %{}}
      end

      {:error, _changeset} =
        ChangeNodeClusterForm.changeset(%{"cluster_name" => "-bad"}, counting_fn)

      assert :counters.get(called, 1) == 0
    end

    test "cluster existence is not checked when name is missing" do
      called = :counters.new(1, [])

      counting_fn = fn _name ->
        :counters.add(called, 1, 1)
        {:ok, %{}}
      end

      {:error, _changeset} = ChangeNodeClusterForm.changeset(%{}, counting_fn)
      assert :counters.get(called, 1) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/2 — invalid params" do
    test "non-map params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               ChangeNodeClusterForm.changeset("bad", &cluster_found/1)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "nil params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               ChangeNodeClusterForm.changeset(nil, &cluster_found/1)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
