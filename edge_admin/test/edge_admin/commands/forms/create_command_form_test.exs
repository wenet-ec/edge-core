# edge_admin/test/edge_admin/commands/forms/create_command_form_test.exs
defmodule EdgeAdmin.Commands.Forms.CreateCommandFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Forms.CreateCommandForm

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "command_text" => "echo hello",
        "targeting" => %{"type" => "all"}
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "all targeting type with command_text succeeds" do
      assert {:ok, result} = CreateCommandForm.changeset(valid_attrs())
      assert result["command_text"] == "echo hello"
      assert result["targeting"]["type"] == "all"
    end

    test "nodes targeting type with node_ids succeeds" do
      node_id = Ecto.UUID.generate()

      attrs =
        valid_attrs(%{
          "targeting" => %{"type" => "nodes", "node_ids" => [node_id]}
        })

      assert {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["targeting"]["type"] == "nodes"
      assert result["targeting"]["node_ids"] == [node_id]
    end

    test "clusters targeting type with cluster_names succeeds" do
      attrs =
        valid_attrs(%{
          "targeting" => %{"type" => "clusters", "cluster_names" => ["prod", "staging"]}
        })

      assert {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["targeting"]["type"] == "clusters"
      assert result["targeting"]["cluster_names"] == ["prod", "staging"]
    end

    test "optional timeout is accepted when positive" do
      attrs = valid_attrs(%{"timeout" => 5000})
      assert {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["timeout"] == 5000
    end

    test "timeout is excluded from result when not provided" do
      assert {:ok, result} = CreateCommandForm.changeset(valid_attrs())
      refute Map.has_key?(result, "timeout")
    end

    test "wrapped command params are unwrapped (atom key)" do
      attrs = %{command: valid_attrs()}
      assert {:ok, _result} = CreateCommandForm.changeset(attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — command_text validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — command_text validation" do
    test "empty command_text is rejected" do
      attrs = valid_attrs(%{"command_text" => ""})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{command_text: [_msg]} = errors_on(changeset)
    end

    test "whitespace-only command_text is rejected" do
      attrs = valid_attrs(%{"command_text" => "   "})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{command_text: [_msg]} = errors_on(changeset)
    end

    test "missing command_text is rejected" do
      attrs = Map.delete(valid_attrs(), "command_text")
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{command_text: [_msg]} = errors_on(changeset)
    end

    test "tab-only command_text is rejected" do
      attrs = valid_attrs(%{"command_text" => "\t\t"})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{command_text: [_msg]} = errors_on(changeset)
    end

    test "command_text with leading/trailing whitespace but non-empty content is accepted" do
      attrs = valid_attrs(%{"command_text" => "  echo hello  "})
      assert {:ok, _result} = CreateCommandForm.changeset(attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — timeout validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — timeout validation" do
    test "zero timeout is rejected" do
      attrs = valid_attrs(%{"timeout" => 0})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{timeout: [msg]} = errors_on(changeset)
      assert msg =~ "positive"
    end

    test "negative timeout is rejected" do
      attrs = valid_attrs(%{"timeout" => -1})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{timeout: [msg]} = errors_on(changeset)
      assert msg =~ "positive"
    end

    test "nil timeout is allowed (optional field)" do
      attrs = valid_attrs(%{"timeout" => nil})
      assert {:ok, _result} = CreateCommandForm.changeset(attrs)
    end

    test "1ms timeout is accepted (boundary)" do
      attrs = valid_attrs(%{"timeout" => 1})
      assert {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["timeout"] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — targeting_type validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — targeting_type validation" do
    test "invalid targeting type is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "specific"}})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{targeting_type: [_msg]} = errors_on(changeset)
    end

    test "missing targeting type is rejected" do
      attrs = valid_attrs(%{"targeting" => %{}})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{targeting_type: [_msg]} = errors_on(changeset)
    end

    test "all three valid targeting types are accepted" do
      for type <- ["all", "nodes", "clusters"] do
        node_ids = if type == "nodes", do: [Ecto.UUID.generate()]
        cluster_names = if type == "clusters", do: ["prod"]

        targeting =
          %{"type" => type}
          |> then(fn t -> if node_ids, do: Map.put(t, "node_ids", node_ids), else: t end)
          |> then(fn t ->
            if cluster_names, do: Map.put(t, "cluster_names", cluster_names), else: t
          end)

        attrs = valid_attrs(%{"targeting" => targeting})
        assert {:ok, _} = CreateCommandForm.changeset(attrs), "expected ok for type=#{type}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — targeting requirements
  # ---------------------------------------------------------------------------

  describe "changeset/1 — targeting requirements" do
    test "nodes type without node_ids is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes"}})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{node_ids: [msg]} = errors_on(changeset)
      assert msg =~ "nodes"
    end

    test "nodes type with empty node_ids is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes", "node_ids" => []}})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{node_ids: [_msg]} = errors_on(changeset)
    end

    test "clusters type without cluster_names is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "clusters"}})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{cluster_names: [msg]} = errors_on(changeset)
      assert msg =~ "clusters"
    end

    test "clusters type with empty cluster_names is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "clusters", "cluster_names" => []}})
      assert {:error, changeset} = CreateCommandForm.changeset(attrs)
      assert %{cluster_names: [_msg]} = errors_on(changeset)
    end

    test "all type does not require node_ids or cluster_names" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "all"}})
      assert {:ok, _result} = CreateCommandForm.changeset(attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output structure
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output structure" do
    test "result has command_text key" do
      {:ok, result} = CreateCommandForm.changeset(valid_attrs())
      assert Map.has_key?(result, "command_text")
    end

    test "result has targeting key with type" do
      {:ok, result} = CreateCommandForm.changeset(valid_attrs())
      assert get_in(result, ["targeting", "type"]) == "all"
    end

    test "nodes result includes node_ids in targeting" do
      node_id = Ecto.UUID.generate()
      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes", "node_ids" => [node_id]}})
      {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["targeting"]["node_ids"] == [node_id]
    end

    test "clusters result includes cluster_names in targeting" do
      attrs =
        valid_attrs(%{"targeting" => %{"type" => "clusters", "cluster_names" => ["prod"]}})

      {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["targeting"]["cluster_names"] == ["prod"]
    end

    test "extra targeting fields from original attrs are preserved" do
      attrs =
        valid_attrs(%{
          "targeting" => %{
            "type" => "all",
            "extra_field" => "preserved"
          }
        })

      {:ok, result} = CreateCommandForm.changeset(attrs)
      assert result["targeting"]["extra_field"] == "preserved"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateCommandForm.changeset("not_a_map")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateCommandForm.changeset(nil)
      end
    end
  end
end
