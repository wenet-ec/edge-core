# edge_admin/test/edge_admin/nodes/forms/create_alias_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.CreateAliasFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.CreateAliasForm

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
    test "simple lowercase name succeeds" do
      assert {:ok, %{"name" => "web"}} = CreateAliasForm.changeset(%{"name" => "web"})
    end

    test "single character name is valid (min length is 1)" do
      assert {:ok, %{"name" => "a"}} = CreateAliasForm.changeset(%{"name" => "a"})
    end

    test "name with hyphens succeeds" do
      assert {:ok, %{"name" => "web-server"}} =
               CreateAliasForm.changeset(%{"name" => "web-server"})
    end

    test "name with digits succeeds" do
      assert {:ok, %{"name" => "node01"}} = CreateAliasForm.changeset(%{"name" => "node01"})
    end

    test "63-character name is valid (max length)" do
      name = String.duplicate("a", 63)
      assert {:ok, %{"name" => ^name}} = CreateAliasForm.changeset(%{"name" => name})
    end

    test "wrapped alias params are unwrapped (atom key)" do
      assert {:ok, %{"name" => "web"}} =
               CreateAliasForm.changeset(%{alias: %{name: "web"}})
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — name format validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — name format validation" do
    test "uppercase letters are rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => "Web"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "leading hyphen is rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => "-web"})
      assert %{name: [msg]} = errors_on(changeset)
      assert msg =~ "hyphen"
    end

    test "trailing hyphen is rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => "web-"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "special characters are rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => "web_server"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "spaces are rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => "web server"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "64-character name exceeds max length" do
      name = String.duplicate("a", 64)
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => name})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "empty name is rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{"name" => ""})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "missing name is rejected" do
      assert {:error, changeset} = CreateAliasForm.changeset(%{})
      assert %{name: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateAliasForm.changeset("not_a_map")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateAliasForm.changeset(nil)
      end
    end
  end
end
