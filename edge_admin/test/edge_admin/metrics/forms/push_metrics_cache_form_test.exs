# edge_admin/test/edge_admin/metrics/forms/push_metrics_cache_form_test.exs
defmodule EdgeAdmin.Metrics.Forms.PushMetricsCacheFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Forms.PushMetricsCacheForm

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{"metrics_type" => "host", "metrics_text" => "# HELP node_cpu_seconds_total\nnode_cpu_seconds_total 1.0"},
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid metrics_type values" do
    test "host metrics_type is accepted" do
      assert {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs(%{"metrics_type" => "host"}))
      assert result["metrics_type"] == "host"
    end

    test "agent metrics_type is accepted" do
      assert {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs(%{"metrics_type" => "agent"}))
      assert result["metrics_type"] == "agent"
    end

    test "wireguard metrics_type is accepted" do
      assert {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs(%{"metrics_type" => "wireguard"}))
      assert result["metrics_type"] == "wireguard"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — metrics_type validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — metrics_type validation" do
    test "missing metrics_type is rejected" do
      attrs = Map.delete(valid_attrs(), "metrics_type")
      assert {:error, changeset} = PushMetricsCacheForm.changeset(attrs)
      assert %{metrics_type: [_msg]} = errors_on(changeset)
    end

    test "invalid metrics_type is rejected" do
      attrs = valid_attrs(%{"metrics_type" => "cpu"})
      assert {:error, changeset} = PushMetricsCacheForm.changeset(attrs)
      assert %{metrics_type: [msg]} = errors_on(changeset)
      assert msg =~ "host"
      assert msg =~ "agent"
      assert msg =~ "wireguard"
    end

    test "empty metrics_type is rejected" do
      attrs = valid_attrs(%{"metrics_type" => ""})
      assert {:error, changeset} = PushMetricsCacheForm.changeset(attrs)
      assert %{metrics_type: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — metrics_text validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — metrics_text validation" do
    test "missing metrics_text is rejected" do
      attrs = Map.delete(valid_attrs(), "metrics_text")
      assert {:error, changeset} = PushMetricsCacheForm.changeset(attrs)
      assert %{metrics_text: [_msg]} = errors_on(changeset)
    end

    test "empty metrics_text is rejected" do
      attrs = valid_attrs(%{"metrics_text" => ""})
      assert {:error, changeset} = PushMetricsCacheForm.changeset(attrs)
      assert %{metrics_text: [_msg]} = errors_on(changeset)
    end

    test "non-empty metrics_text is accepted" do
      attrs = valid_attrs(%{"metrics_text" => "# HELP some_metric\nsome_metric 42"})
      assert {:ok, result} = PushMetricsCacheForm.changeset(attrs)
      assert result["metrics_text"] == "# HELP some_metric\nsome_metric 42"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "result has string key metrics_type" do
      {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs())
      assert Map.has_key?(result, "metrics_type")
    end

    test "result has string key metrics_text" do
      {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs())
      assert Map.has_key?(result, "metrics_text")
    end

    test "result contains exactly metrics_type and metrics_text" do
      {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs())
      assert result |> Map.keys() |> Enum.sort() == ["metrics_text", "metrics_type"]
    end

    test "metrics_text value is preserved exactly" do
      text = "# HELP node_load1 1 minute load average\nnode_load1 0.42"
      {:ok, result} = PushMetricsCacheForm.changeset(valid_attrs(%{"metrics_text" => text}))
      assert result["metrics_text"] == text
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = PushMetricsCacheForm.changeset("not_a_map")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "nil params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} = PushMetricsCacheForm.changeset(nil)
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
