# edge_admin/test/edge_admin/nodes/targeting_test.exs
defmodule EdgeAdmin.Nodes.TargetingTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Targeting

  # ---------------------------------------------------------------------------
  # peri_schema/0 — shape sanity (the canonical layer-1 schema for any
  # operation that targets a fleet subset). MCP consumes this directly, so
  # changes here ripple to every targeting-aware tool.
  # ---------------------------------------------------------------------------

  describe "peri_schema/0" do
    test "is a map with the documented top-level keys" do
      schema = Targeting.peri_schema()

      assert is_map(schema)
      assert Map.has_key?(schema, :type)
      assert Map.has_key?(schema, :node_ids)
      assert Map.has_key?(schema, :cluster_names)
      assert Map.has_key?(schema, :node_filters)
      assert Map.has_key?(schema, :cluster_filters)
    end

    test "type is required and constrained to the three documented values" do
      assert {:required, {:enum, ["all", "nodes", "clusters"]}} = Targeting.peri_schema().type
    end

    test "node_ids and cluster_names are list-of-string when present" do
      schema = Targeting.peri_schema()
      assert schema.node_ids == {:list, :string}
      assert schema.cluster_names == {:list, :string}
    end

    test "node_filters allows the documented status values" do
      schema = Targeting.peri_schema()
      assert {:enum, ["healthy", "unhealthy", "unreachable"]} = schema.node_filters.status
    end

    test "node_filters allows the documented id_type values" do
      schema = Targeting.peri_schema()
      assert {:enum, ["persistent", "random"]} = schema.node_filters.id_type
    end
  end

  # ---------------------------------------------------------------------------
  # validate_iso8601_date_or_datetime/1
  # ---------------------------------------------------------------------------

  describe "validate_iso8601_date_or_datetime/1" do
    test "accepts a full ISO 8601 datetime with UTC offset" do
      assert {:ok, "2025-01-15T12:34:56Z"} =
               Targeting.validate_iso8601_date_or_datetime("2025-01-15T12:34:56Z")
    end

    test "accepts a datetime with non-Z offset" do
      assert {:ok, "2025-01-15T12:34:56+02:00"} =
               Targeting.validate_iso8601_date_or_datetime("2025-01-15T12:34:56+02:00")
    end

    test "accepts a bare ISO 8601 date" do
      assert {:ok, "2025-01-15"} = Targeting.validate_iso8601_date_or_datetime("2025-01-15")
    end

    test "preserves the original string (no DateTime/Date promotion)" do
      # Crucial — values get JSON-serialized into JSONB and read back as
      # strings, so we explicitly do NOT promote to %DateTime{} / %Date{}.
      input = "2025-01-15T12:34:56Z"
      assert {:ok, ^input} = Targeting.validate_iso8601_date_or_datetime(input)
    end

    test "rejects malformed datetime strings" do
      assert {:error, _msg, _opts} = Targeting.validate_iso8601_date_or_datetime("not a date")

      assert {:error, _msg, _opts} =
               Targeting.validate_iso8601_date_or_datetime("2025-13-99T99:99:99Z")

      # US-style date — neither ISO datetime nor ISO date.
      assert {:error, _msg, _opts} = Targeting.validate_iso8601_date_or_datetime("01/15/2025")
    end

    test "rejects empty string" do
      assert {:error, _msg, _opts} = Targeting.validate_iso8601_date_or_datetime("")
    end

    test "rejects non-binary inputs" do
      assert {:error, _msg, _opts} = Targeting.validate_iso8601_date_or_datetime(nil)
      assert {:error, _msg, _opts} = Targeting.validate_iso8601_date_or_datetime(12_345)
      assert {:error, _msg, _opts} = Targeting.validate_iso8601_date_or_datetime(%{})
    end

    test "error opts include the offending value for inclusion in the rendered message" do
      {:error, msg, opts} = Targeting.validate_iso8601_date_or_datetime("garbage")

      assert msg =~ "ISO 8601"
      assert Keyword.has_key?(opts, :value)
    end
  end
end
