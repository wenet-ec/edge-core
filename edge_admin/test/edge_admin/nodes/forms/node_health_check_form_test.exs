# edge_admin/test/edge_admin/nodes/forms/node_health_check_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.NodeHealthCheckFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.NodeHealthCheckForm

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid statuses
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid statuses" do
    test "healthy status succeeds" do
      assert {:ok, result} = NodeHealthCheckForm.changeset(%{"status" => "healthy"})
      assert result["status"] == "healthy"
    end

    test "unhealthy status succeeds" do
      assert {:ok, result} = NodeHealthCheckForm.changeset(%{"status" => "unhealthy"})
      assert result["status"] == "unhealthy"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid statuses
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid statuses" do
    test "unreachable status is rejected" do
      assert {:error, changeset} = NodeHealthCheckForm.changeset(%{"status" => "unreachable"})
      assert %{status: [msg]} = errors_on(changeset)
      assert msg =~ "healthy"
      assert msg =~ "unhealthy"
    end

    test "unknown status is rejected" do
      assert {:error, changeset} = NodeHealthCheckForm.changeset(%{"status" => "degraded"})
      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "empty status string is rejected" do
      assert {:error, changeset} = NodeHealthCheckForm.changeset(%{"status" => ""})
      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "missing status is rejected" do
      assert {:error, changeset} = NodeHealthCheckForm.changeset(%{})
      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "uppercase status is rejected" do
      assert {:error, changeset} = NodeHealthCheckForm.changeset(%{"status" => "Healthy"})
      assert %{status: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output (stringify_keys)
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "result map has string key 'status', not atom :status" do
      {:ok, result} = NodeHealthCheckForm.changeset(%{"status" => "healthy"})
      assert Map.has_key?(result, "status")
      refute Map.has_key?(result, :status)
    end

    test "result value is preserved as-is" do
      {:ok, result} = NodeHealthCheckForm.changeset(%{"status" => "unhealthy"})
      assert result["status"] == "unhealthy"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        NodeHealthCheckForm.changeset("not_a_map")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        NodeHealthCheckForm.changeset(nil)
      end
    end
  end
end
