# edge_admin/test/edge_admin/nodes/forms/create_cluster_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.CreateClusterFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.CreateClusterForm

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24"}, overrides)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — node_limit validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — node_limit field" do
    test "valid node_limit is accepted" do
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs(%{"node_limit" => 10}))
      assert result["node_limit"] == 10
    end

    test "node_limit of 1 is accepted (minimum allowed)" do
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs(%{"node_limit" => 1}))
      assert result["node_limit"] == 1
    end

    test "node_limit of 0 is rejected (must be greater than 0)" do
      assert {:error, changeset} = CreateClusterForm.changeset(valid_attrs(%{"node_limit" => 0}))
      assert %{node_limit: [_msg]} = errors_on(changeset)
    end

    test "negative node_limit is rejected" do
      assert {:error, changeset} = CreateClusterForm.changeset(valid_attrs(%{"node_limit" => -1}))
      assert %{node_limit: [_msg]} = errors_on(changeset)
    end

    test "nil node_limit is excluded from result (no limit means unlimited)" do
      {:ok, result} = CreateClusterForm.changeset(valid_attrs())
      refute Map.has_key?(result, "node_limit")
    end

    test "omitted node_limit is excluded from result" do
      {:ok, result} = CreateClusterForm.changeset(valid_attrs())
      refute Map.has_key?(result, "node_limit")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "valid name and ipv4_range succeeds" do
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs())
      assert result["name"] == "prod"
      assert result["ipv4_range"] == "100.64.1.0/24"
    end

    test "name is required" do
      assert {:error, changeset} = CreateClusterForm.changeset(%{"ipv4_range" => "100.64.1.0/24"})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "ipv4_range is optional at form level" do
      assert {:ok, result} = CreateClusterForm.changeset(%{"name" => "prod"})
      refute Map.has_key?(result, "ipv4_range")
    end

    test "24-character name is valid (max length boundary)" do
      name = String.duplicate("a", 24)
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs(%{"name" => name}))
      assert result["name"] == name
    end

    test "name with hyphens succeeds" do
      assert {:ok, result} =
               CreateClusterForm.changeset(valid_attrs(%{"name" => "my-cluster"}))

      assert result["name"] == "my-cluster"
    end

    test "name with digits succeeds" do
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs(%{"name" => "cluster01"}))
      assert result["name"] == "cluster01"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — name format validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — name format validation" do
    test "uppercase letters are rejected" do
      assert {:error, changeset} = CreateClusterForm.changeset(valid_attrs(%{"name" => "Prod"}))
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "leading hyphen is rejected" do
      assert {:error, changeset} =
               CreateClusterForm.changeset(valid_attrs(%{"name" => "-prod"}))

      assert %{name: [msg]} = errors_on(changeset)
      assert msg =~ "hyphen"
    end

    test "trailing hyphen is rejected" do
      assert {:error, changeset} =
               CreateClusterForm.changeset(valid_attrs(%{"name" => "prod-"}))

      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "underscore is rejected" do
      assert {:error, changeset} =
               CreateClusterForm.changeset(valid_attrs(%{"name" => "my_cluster"}))

      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "25-character name exceeds max length" do
      name = String.duplicate("a", 25)

      assert {:error, changeset} = CreateClusterForm.changeset(valid_attrs(%{"name" => name}))
      assert %{name: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — reserved names
  # ---------------------------------------------------------------------------

  describe "changeset/1 — reserved names" do
    test "name 'default' is rejected as reserved" do
      assert {:error, changeset} = CreateClusterForm.changeset(valid_attrs(%{"name" => "default"}))
      assert %{name: [msg]} = errors_on(changeset)
      assert msg =~ "reserved"
    end

    test "names containing 'default' as a substring are accepted" do
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs(%{"name" => "my-default"}))
      assert result["name"] == "my-default"
    end

    test "name 'default-prod' is accepted (only the bare 'default' is reserved)" do
      assert {:ok, result} = CreateClusterForm.changeset(valid_attrs(%{"name" => "default-prod"}))
      assert result["name"] == "default-prod"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — ipv4_range format validation (shallow regex check)
  # ---------------------------------------------------------------------------

  describe "changeset/1 — ipv4_range format validation" do
    test "valid /24 CIDR passes" do
      assert {:ok, _} = CreateClusterForm.changeset(valid_attrs(%{"ipv4_range" => "10.0.0.0/24"}))
    end

    test "valid /10 CIDR passes" do
      assert {:ok, _} =
               CreateClusterForm.changeset(valid_attrs(%{"ipv4_range" => "100.64.0.0/10"}))
    end

    test "missing prefix slash is rejected" do
      assert {:error, changeset} =
               CreateClusterForm.changeset(valid_attrs(%{"ipv4_range" => "100.64.0.0"}))

      assert %{ipv4_range: [msg]} = errors_on(changeset)
      assert msg =~ "CIDR"
    end

    test "text string is rejected" do
      assert {:error, changeset} =
               CreateClusterForm.changeset(valid_attrs(%{"ipv4_range" => "not-a-cidr"}))

      assert %{ipv4_range: [_msg]} = errors_on(changeset)
    end

    test "missing octets is rejected" do
      assert {:error, changeset} =
               CreateClusterForm.changeset(valid_attrs(%{"ipv4_range" => "100.64/24"}))

      assert %{ipv4_range: [_msg]} = errors_on(changeset)
    end

    test "form regex allows out-of-range octets (deep validation is schema's job)" do
      # The form only checks the pattern x.x.x.x/xx — semantic validation happens in Cluster schema
      assert {:ok, _} =
               CreateClusterForm.changeset(valid_attrs(%{"ipv4_range" => "999.999.999.999/99"}))
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil values are excluded from result" do
      {:ok, result} = CreateClusterForm.changeset(%{"name" => "prod"})
      refute Map.has_key?(result, "ipv4_range")
    end

    test "both fields present when both provided" do
      {:ok, result} = CreateClusterForm.changeset(valid_attrs())
      assert Map.has_key?(result, "name")
      assert Map.has_key?(result, "ipv4_range")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateClusterForm.changeset("not_a_map")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateClusterForm.changeset(nil)
      end
    end
  end
end
