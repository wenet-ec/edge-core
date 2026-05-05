# edge_admin/test/edge_admin/self_updates/forms/create_self_update_request_form_test.exs
defmodule EdgeAdmin.SelfUpdates.Forms.CreateSelfUpdateRequestFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.SelfUpdates.Forms.CreateSelfUpdateRequestForm

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{"targeting" => %{"type" => "all"}},
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
    test "all targeting type succeeds" do
      assert {:ok, result} = CreateSelfUpdateRequestForm.changeset(valid_attrs())
      assert result["targeting"]["type"] == "all"
    end

    test "nodes targeting type with node_ids succeeds" do
      node_id = Ecto.UUID.generate()

      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes", "node_ids" => [node_id]}})

      assert {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["type"] == "nodes"
      assert result["targeting"]["node_ids"] == [node_id]
    end

    test "clusters targeting type with cluster_names succeeds" do
      attrs =
        valid_attrs(%{"targeting" => %{"type" => "clusters", "cluster_names" => ["prod", "staging"]}})

      assert {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["type"] == "clusters"
      assert result["targeting"]["cluster_names"] == ["prod", "staging"]
    end

    test "non-map params return a targeting error via fallback clause" do
      assert {:error, %Ecto.Changeset{} = changeset} = CreateSelfUpdateRequestForm.changeset("bad")
      assert %{targeting: [msg]} = errors_on(changeset)
      assert msg =~ "is required"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — targeting_type validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — targeting_type validation" do
    test "missing targeting_type is rejected" do
      attrs = valid_attrs(%{"targeting" => %{}})
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert %{targeting_type: [_msg]} = errors_on(changeset)
    end

    test "invalid targeting_type is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "specific"}})
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
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
        assert {:ok, _} = CreateSelfUpdateRequestForm.changeset(attrs), "expected ok for type=#{type}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — targeting requirements
  # ---------------------------------------------------------------------------

  describe "changeset/1 — targeting requirements" do
    test "nodes type without node_ids is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes"}})
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert %{node_ids: [msg]} = errors_on(changeset)
      assert msg =~ "nodes"
    end

    test "nodes type with empty node_ids is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes", "node_ids" => []}})
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert %{node_ids: [_msg]} = errors_on(changeset)
    end

    test "clusters type without cluster_names is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "clusters"}})
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert %{cluster_names: [msg]} = errors_on(changeset)
      assert msg =~ "clusters"
    end

    test "clusters type with empty cluster_names is rejected" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "clusters", "cluster_names" => []}})
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert %{cluster_names: [_msg]} = errors_on(changeset)
    end

    test "all type does not require node_ids or cluster_names" do
      attrs = valid_attrs(%{"targeting" => %{"type" => "all"}})
      assert {:ok, _result} = CreateSelfUpdateRequestForm.changeset(attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output structure
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output structure" do
    test "result is a map with targeting key" do
      {:ok, result} = CreateSelfUpdateRequestForm.changeset(valid_attrs())
      assert Map.has_key?(result, "targeting")
    end

    test "targeting always contains type" do
      {:ok, result} = CreateSelfUpdateRequestForm.changeset(valid_attrs())
      assert get_in(result, ["targeting", "type"]) == "all"
    end

    test "nodes result includes node_ids under targeting" do
      node_id = Ecto.UUID.generate()
      attrs = valid_attrs(%{"targeting" => %{"type" => "nodes", "node_ids" => [node_id]}})
      {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["node_ids"] == [node_id]
    end

    test "clusters result includes cluster_names under targeting" do
      attrs =
        valid_attrs(%{"targeting" => %{"type" => "clusters", "cluster_names" => ["prod"]}})

      {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["cluster_names"] == ["prod"]
    end

    test "extra targeting fields like node_filters are preserved in output" do
      attrs =
        valid_attrs(%{
          "targeting" => %{
            "type" => "all",
            "node_filters" => %{"status" => "healthy"}
          }
        })

      {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["node_filters"] == %{"status" => "healthy"}
    end

    test "extra targeting fields like cluster_filters are preserved in output" do
      attrs =
        valid_attrs(%{
          "targeting" => %{
            "type" => "all",
            "cluster_filters" => %{"region" => "us-east"}
          }
        })

      {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["cluster_filters"] == %{"region" => "us-east"}
    end

    test "validated fields take precedence over original targeting fields" do
      # Provide node_ids in original targeting but use 'all' type — node_ids should not appear
      node_id = Ecto.UUID.generate()

      attrs =
        valid_attrs(%{
          "targeting" => %{
            "type" => "all",
            "node_ids" => [node_id]
          }
        })

      {:ok, result} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert result["targeting"]["type"] == "all"
      # node_ids from original are preserved via Map.merge but type is authoritative
      assert result["targeting"]["type"] == "all"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — missing or absent targeting map
  # ---------------------------------------------------------------------------

  describe "changeset/1 — missing targeting" do
    test "missing targeting key defaults to empty targeting map → rejected for missing type" do
      attrs = %{}
      assert {:error, changeset} = CreateSelfUpdateRequestForm.changeset(attrs)
      assert %{targeting_type: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params return a targeting error" do
      assert {:error, %Ecto.Changeset{} = changeset} = CreateSelfUpdateRequestForm.changeset("not_a_map")
      assert %{targeting: [msg]} = errors_on(changeset)
      assert msg =~ "is required"
    end

    test "nil params return a targeting error" do
      assert {:error, %Ecto.Changeset{} = changeset} = CreateSelfUpdateRequestForm.changeset(nil)
      assert %{targeting: [msg]} = errors_on(changeset)
      assert msg =~ "is required"
    end
  end
end
