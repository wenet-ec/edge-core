# edge_admin/test/edge_admin_mcp/flop_params_test.exs
defmodule EdgeAdminMcp.FlopParamsTest do
  use ExUnit.Case, async: true

  alias EdgeAdminMcp.FlopParams

  # ---------------------------------------------------------------------------
  # build/1 — auto-detection: no per-tool opts needed.
  # Every MCP param key is translated by pattern.
  # ---------------------------------------------------------------------------

  describe "build/1 — pagination defaults" do
    test "defaults page to 1 and page_size to 20 when not supplied" do
      result = FlopParams.build(%{})

      assert result["page"] == 1
      assert result["page_size"] == 20
    end

    test "passes through supplied page and page_size" do
      result = FlopParams.build(%{page: 3, page_size: 50})

      assert result["page"] == 3
      assert result["page_size"] == 50
    end

    test "default_page_size opt overrides the default" do
      result = FlopParams.build(%{}, default_page_size: 100)

      assert result["page_size"] == 100
    end

    test "supplied page_size wins over default_page_size opt" do
      result = FlopParams.build(%{page_size: 50}, default_page_size: 100)

      assert result["page_size"] == 50
    end
  end

  # ---------------------------------------------------------------------------
  # Plain fields (string/integer) — passed through as-is
  # ---------------------------------------------------------------------------

  describe "build/1 — plain string/integer fields" do
    test "plain string field is passed through unchanged" do
      result = FlopParams.build(%{cluster_name: "prod"})

      assert result["cluster_name"] == "prod"
    end

    test "plain integer field is passed through unchanged" do
      result = FlopParams.build(%{exit_code: 1})

      assert result["exit_code"] == 1
    end

    test "nil value is dropped" do
      result = FlopParams.build(%{cluster_name: nil})

      refute Map.has_key?(result, "cluster_name")
    end

    test "multiple plain fields are each passed through" do
      result = FlopParams.build(%{cluster_name: "prod", version: "1.0.*"})

      assert result["cluster_name"] == "prod"
      assert result["version"] == "1.0.*"
    end
  end

  # ---------------------------------------------------------------------------
  # Boolean fields — native true/false pass through; nil is dropped
  # ---------------------------------------------------------------------------

  describe "build/1 — boolean fields" do
    test "native true passes through" do
      result = FlopParams.build(%{has_node_limit: true})

      assert result["has_node_limit"] == true
    end

    test "native false passes through" do
      result = FlopParams.build(%{has_node_limit: false})

      assert result["has_node_limit"] == false
    end

    test "nil boolean is dropped — no filter applied" do
      result = FlopParams.build(%{has_node_limit: nil})

      refute Map.has_key?(result, "has_node_limit")
    end
  end

  # ---------------------------------------------------------------------------
  # _in fields — list → "<field>__in" comma-joined string
  # ---------------------------------------------------------------------------

  describe "build/1 — _in list fields" do
    test "list is joined and emitted as <field>__in" do
      result = FlopParams.build(%{node_id_in: ["uuid-1", "uuid-2", "uuid-3"]})

      assert result["node_id__in"] == "uuid-1,uuid-2,uuid-3"
    end

    test "single-element list produces no trailing comma" do
      result = FlopParams.build(%{cluster_name_in: ["prod"]})

      assert result["cluster_name__in"] == "prod"
    end

    test "empty list is dropped" do
      result = FlopParams.build(%{node_id_in: []})

      refute Map.has_key?(result, "node_id__in")
    end

    test "nil list is dropped" do
      result = FlopParams.build(%{node_id_in: nil})

      refute Map.has_key?(result, "node_id__in")
    end

    test "enum list is joined correctly" do
      result = FlopParams.build(%{status_in: ["healthy", "unhealthy"]})

      assert result["status__in"] == "healthy,unhealthy"
    end

    test "multiple _in fields are each translated independently" do
      result = FlopParams.build(%{node_id_in: ["a", "b"], cluster_name_in: ["prod", "staging"]})

      assert result["node_id__in"] == "a,b"
      assert result["cluster_name__in"] == "prod,staging"
    end
  end

  # ---------------------------------------------------------------------------
  # _gte / _lte fields — single underscore → double underscore
  # ---------------------------------------------------------------------------

  describe "build/1 — range fields (_gte / _lte)" do
    test "_gte suffix becomes __gte" do
      result = FlopParams.build(%{inserted_at_gte: "2025-01-01T00:00:00Z"})

      assert result["inserted_at__gte"] == "2025-01-01T00:00:00Z"
    end

    test "_lte suffix becomes __lte" do
      result = FlopParams.build(%{inserted_at_lte: "2025-02-01T00:00:00Z"})

      assert result["inserted_at__lte"] == "2025-02-01T00:00:00Z"
    end

    test "both sides of a range are translated" do
      result =
        FlopParams.build(%{
          inserted_at_gte: "2025-01-01T00:00:00Z",
          inserted_at_lte: "2025-02-01T00:00:00Z"
        })

      assert result["inserted_at__gte"] == "2025-01-01T00:00:00Z"
      assert result["inserted_at__lte"] == "2025-02-01T00:00:00Z"
    end

    test "single-side range emits only that side" do
      result = FlopParams.build(%{timeout_gte: 1000})

      assert result["timeout__gte"] == 1000
      refute Map.has_key?(result, "timeout__lte")
    end

    test "nil range values are dropped" do
      result = FlopParams.build(%{timeout_gte: nil, timeout_lte: nil})

      refute Map.has_key?(result, "timeout__gte")
      refute Map.has_key?(result, "timeout__lte")
    end

    test "integer range value passes through correctly" do
      result = FlopParams.build(%{exit_code_gte: 1})

      assert result["exit_code__gte"] == 1
    end

    test "multiple range fields each get their own __gte/__lte pair" do
      result =
        FlopParams.build(%{
          inserted_at_gte: "2025-01-01",
          updated_at_lte: "2025-02-01",
          timeout_gte: 1000
        })

      assert result["inserted_at__gte"] == "2025-01-01"
      assert result["updated_at__lte"] == "2025-02-01"
      assert result["timeout__gte"] == 1000
    end
  end

  # ---------------------------------------------------------------------------
  # Reserved keys — page, page_size, order_by, order_directions, event_type
  # ---------------------------------------------------------------------------

  describe "build/1 — reserved keys" do
    test "order_by and order_directions pass through" do
      result = FlopParams.build(%{order_by: "name,inserted_at", order_directions: "asc,desc"})

      assert result["order_by"] == "name,inserted_at"
      assert result["order_directions"] == "asc,desc"
    end

    test "nil sort fields are absent from output" do
      result = FlopParams.build(%{order_by: nil, order_directions: nil})

      refute Map.has_key?(result, "order_by")
      refute Map.has_key?(result, "order_directions")
    end

    test "event_type is skipped by auto-detection (post-filter injected manually by list_webhooks)" do
      result = FlopParams.build(%{event_type: "edge.node.registered"})

      refute Map.has_key?(result, "event_type")
    end
  end

  # ---------------------------------------------------------------------------
  # Full integration — realistic MCP params map
  # ---------------------------------------------------------------------------

  describe "build/1 — full integration" do
    test "produces the correct Flop-shaped map for a realistic list_nodes call" do
      params = %{
        page: 2,
        page_size: 50,
        cluster_name: "prod*",
        cluster_name_in: ["prod-east", "prod-west"],
        status_in: ["healthy", "unhealthy"],
        self_update_enabled: true,
        last_seen_at_gte: "2025-01-01T00:00:00Z",
        inserted_at_lte: "2025-06-01T00:00:00Z",
        order_by: "inserted_at",
        order_directions: "desc"
      }

      result = FlopParams.build(params)

      assert result == %{
               "page" => 2,
               "page_size" => 50,
               "cluster_name" => "prod*",
               "cluster_name__in" => "prod-east,prod-west",
               "status__in" => "healthy,unhealthy",
               "self_update_enabled" => true,
               "last_seen_at__gte" => "2025-01-01T00:00:00Z",
               "inserted_at__lte" => "2025-06-01T00:00:00Z",
               "order_by" => "inserted_at",
               "order_directions" => "desc"
             }
    end

    test "nil values are uniformly dropped across all field types" do
      params = %{
        cluster_name: nil,
        cluster_name_in: nil,
        self_update_enabled: nil,
        inserted_at_gte: nil
      }

      result = FlopParams.build(params)

      refute Map.has_key?(result, "cluster_name")
      refute Map.has_key?(result, "cluster_name__in")
      refute Map.has_key?(result, "self_update_enabled")
      refute Map.has_key?(result, "inserted_at__gte")
    end
  end
end
