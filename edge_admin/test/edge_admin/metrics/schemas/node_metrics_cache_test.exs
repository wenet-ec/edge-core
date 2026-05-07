# edge_admin/test/edge_admin/metrics/schemas/node_metrics_cache_test.exs
defmodule EdgeAdmin.Metrics.Schemas.NodeMetricsCacheTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Schemas.NodeMetricsCache

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        node_id: Ecto.UUID.generate(),
        metrics_type: "host",
        metrics_text: "# HELP node_cpu_seconds_total\nnode_cpu_seconds_total 1.0"
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, valid_attrs())
      assert changeset.valid?
    end

    test "metrics_type accepts host, agent, and wireguard" do
      for type <- ["host", "agent", "wireguard"] do
        changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, valid_attrs(%{metrics_type: type}))
        assert changeset.valid?, "expected #{type} to be valid"
      end
    end

    test "metrics_type rejects anything else" do
      changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, valid_attrs(%{metrics_type: "cpu"}))
      refute changeset.valid?
      assert %{metrics_type: ["is invalid"]} = errors_on(changeset)
    end

    test "node_id is required" do
      attrs = Map.delete(valid_attrs(), :node_id)
      changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, attrs)
      refute changeset.valid?
      assert %{node_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "metrics_type is required" do
      attrs = Map.delete(valid_attrs(), :metrics_type)
      changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, attrs)
      refute changeset.valid?
      # validate_inclusion runs even when blank; required check also fires.
      assert "can't be blank" in (errors_on(changeset)[:metrics_type] || [])
    end

    test "metrics_text is required" do
      attrs = Map.delete(valid_attrs(), :metrics_text)
      changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, attrs)
      refute changeset.valid?
      assert %{metrics_text: ["can't be blank"]} = errors_on(changeset)
    end

    test "ignores unknown fields (cast allowlist)" do
      attrs = valid_attrs(%{not_a_field: "ignored"})
      changeset = NodeMetricsCache.changeset(%NodeMetricsCache{}, attrs)
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :not_a_field)
    end
  end

  # Mirrors Phoenix's Ecto.Changeset error helper without pulling in DataCase
  # (we don't want to start the Repo for these pure-changeset tests).
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
