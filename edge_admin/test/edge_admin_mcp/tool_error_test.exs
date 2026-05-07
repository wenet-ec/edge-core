# edge_admin/test/edge_admin_mcp/tool_error_test.exs
defmodule EdgeAdminMcp.ToolErrorTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ChangesetErrors
  alias EdgeAdminMcp.ToolError

  # ---------------------------------------------------------------------------
  # Cross-surface contract: changeset errors render through the SAME translator
  # as REST's ChangesetJSON. The shared module is EdgeAdmin.ChangesetErrors.
  # If MCP and REST ever diverge in error message text, this is where to look.
  # ---------------------------------------------------------------------------

  defp changeset_with_error(field, message) do
    {%{}, %{name: :string}}
    |> Ecto.Changeset.cast(%{}, [:name])
    |> Ecto.Changeset.add_error(field, message)
  end

  describe "message/1 — changeset" do
    test "delegates to ChangesetErrors.to_flat_string/1 (shared with REST)" do
      cs = changeset_with_error(:name, "can't be blank")

      assert ToolError.message(cs) == ChangesetErrors.to_flat_string(cs)
    end

    test "renders a real error with the documented prefix" do
      cs = changeset_with_error(:name, "can't be blank")

      message = ToolError.message(cs)

      assert message =~ "Validation failed"
      assert message =~ "can't be blank"
    end
  end

  describe "message/1 — domain reasons" do
    test ":not_found" do
      assert ToolError.message(:not_found) == "Resource not found"
    end

    test ":service_unavailable" do
      assert ToolError.message(:service_unavailable) ==
               "A downstream dependency is unavailable — try again shortly"
    end

    test ":degraded_mode" do
      assert ToolError.message(:degraded_mode) ==
               "Cluster is in degraded mode (over capacity) — try again when capacity recovers"
    end
  end

  describe "message/1 — {:conflict, reason}" do
    test "passes the binary reason through unchanged" do
      assert ToolError.message({:conflict, "Already exists"}) == "Already exists"
    end

    test "non-binary conflict reasons fall through to the catch-all (defensive)" do
      # The clause matches only when reason is a binary. A non-binary tuple
      # falls through to the catch-all "An unexpected error occurred".
      assert ToolError.message({:conflict, :atom_reason}) == "An unexpected error occurred"
    end
  end

  describe "message/1 — Flop.Meta" do
    test "renders an invalid-filter message regardless of meta contents" do
      meta = %Flop.Meta{errors: [page: ["is invalid"]]}

      assert ToolError.message(meta) == "Invalid filter or sort parameters"
    end
  end

  describe "message/1 — catch-all" do
    test "unknown atoms render the generic message" do
      assert ToolError.message(:something_weird) == "An unexpected error occurred"
    end

    test "unknown tuples render the generic message" do
      assert ToolError.message({:unknown, "details"}) == "An unexpected error occurred"
    end

    test "bare strings render the generic message" do
      # Strings aren't a documented input — we go through the catch-all rather
      # than echoing them back. Pinning so a future 'helpful pass-through' is
      # an intentional change, not a silent leak of internal error text.
      assert ToolError.message("internal: psql connection refused") ==
               "An unexpected error occurred"
    end

    test "nil renders the generic message" do
      assert ToolError.message(nil) == "An unexpected error occurred"
    end
  end
end
