# edge_admin/test/edge_admin_mcp/flop_params_test.exs
defmodule EdgeAdminMcp.FlopParamsTest do
  use ExUnit.Case, async: true

  alias EdgeAdminMcp.FlopParams

  # ---------------------------------------------------------------------------
  # build/2 — MCP-shape (single underscore) → Flop-shape (double underscore).
  # Output is always string-keyed.
  # ---------------------------------------------------------------------------

  describe "build/2 — pagination defaults" do
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
  # passthrough fields — atom keys → string keys, nil values dropped
  # ---------------------------------------------------------------------------

  describe "build/2 — passthrough" do
    test "copies passthrough atom keys to string keys" do
      result =
        FlopParams.build(%{status: "healthy", name: "prod"}, passthrough: [:status, :name])

      assert result["status"] == "healthy"
      assert result["name"] == "prod"
    end

    test "drops nil passthrough values (so Flop doesn't see them)" do
      result = FlopParams.build(%{status: nil, name: "prod"}, passthrough: [:status, :name])

      refute Map.has_key?(result, "status")
      assert result["name"] == "prod"
    end

    test "ignores keys not declared in :passthrough (allow-list, not pass-everything)" do
      result = FlopParams.build(%{status: "healthy", uninvited: "leak"}, passthrough: [:status])

      assert result["status"] == "healthy"
      refute Map.has_key?(result, "uninvited")
    end

    test "missing passthrough key in params is silently dropped" do
      result = FlopParams.build(%{status: "healthy"}, passthrough: [:status, :missing])

      assert result["status"] == "healthy"
      refute Map.has_key?(result, "missing")
    end
  end

  # ---------------------------------------------------------------------------
  # range fields — _gte / _lte → __gte / __lte (Flop's expected suffix)
  # ---------------------------------------------------------------------------

  describe "build/2 — ranges" do
    test "expands a range field into two double-underscore Flop keys" do
      result =
        FlopParams.build(
          %{inserted_at_gte: "2025-01-01T00:00:00Z", inserted_at_lte: "2025-02-01T00:00:00Z"},
          ranges: [:inserted_at]
        )

      assert result["inserted_at__gte"] == "2025-01-01T00:00:00Z"
      assert result["inserted_at__lte"] == "2025-02-01T00:00:00Z"
    end

    test "single-side range (only gte supplied) emits only that side" do
      result = FlopParams.build(%{timeout_gte: 1000}, ranges: [:timeout])

      assert result["timeout__gte"] == 1000
      refute Map.has_key?(result, "timeout__lte")
    end

    test "single-side range (only lte supplied) emits only that side" do
      result = FlopParams.build(%{timeout_lte: 5000}, ranges: [:timeout])

      assert result["timeout__lte"] == 5000
      refute Map.has_key?(result, "timeout__gte")
    end

    test "nil range values are dropped" do
      result =
        FlopParams.build(%{timeout_gte: nil, timeout_lte: nil}, ranges: [:timeout])

      refute Map.has_key?(result, "timeout__gte")
      refute Map.has_key?(result, "timeout__lte")
    end

    test "multiple range fields each get their own __gte/__lte pair" do
      result =
        FlopParams.build(
          %{
            inserted_at_gte: "2025-01-01",
            updated_at_lte: "2025-02-01",
            timeout_gte: 1000
          },
          ranges: [:inserted_at, :updated_at, :timeout]
        )

      assert result["inserted_at__gte"] == "2025-01-01"
      assert result["updated_at__lte"] == "2025-02-01"
      assert result["timeout__gte"] == 1000
    end

    test "ranges that aren't in :ranges opt are NOT expanded (allow-list)" do
      result = FlopParams.build(%{inserted_at_gte: "2025-01-01"}, ranges: [])

      refute Map.has_key?(result, "inserted_at__gte")
    end
  end

  # ---------------------------------------------------------------------------
  # sort fields — order_by + order_directions, dropped when nil
  # ---------------------------------------------------------------------------

  describe "build/2 — sort" do
    test "passes order_by and order_directions through" do
      result = FlopParams.build(%{order_by: "name,inserted_at", order_directions: "asc,desc"})

      assert result["order_by"] == "name,inserted_at"
      assert result["order_directions"] == "asc,desc"
    end

    test "drops nil sort fields" do
      result = FlopParams.build(%{order_by: nil, order_directions: nil})

      refute Map.has_key?(result, "order_by")
      refute Map.has_key?(result, "order_directions")
    end

    test "missing sort fields are absent from output" do
      result = FlopParams.build(%{})

      refute Map.has_key?(result, "order_by")
      refute Map.has_key?(result, "order_directions")
    end

    test "sort and pagination coexist" do
      result = FlopParams.build(%{page: 2, order_by: "name"})

      assert result["page"] == 2
      assert result["order_by"] == "name"
    end
  end

  # ---------------------------------------------------------------------------
  # multi fields — {:array, :string} lists joined to comma-separated strings
  # so RequestParser picks them up as op: :in filters (same wire format as REST)
  # ---------------------------------------------------------------------------

  describe "build/2 — multi" do
    test "joins a list value into a comma-separated string" do
      result =
        FlopParams.build(%{node_ids: ["uuid-1", "uuid-2", "uuid-3"]}, multi: [:node_ids])

      assert result["node_ids"] == "uuid-1,uuid-2,uuid-3"
    end

    test "single-element list produces a plain string (no trailing comma)" do
      result = FlopParams.build(%{cluster_names: ["prod"]}, multi: [:cluster_names])

      assert result["cluster_names"] == "prod"
    end

    test "nil value is dropped (not in params)" do
      result = FlopParams.build(%{node_ids: nil}, multi: [:node_ids])

      refute Map.has_key?(result, "node_ids")
    end

    test "empty list is dropped (treated like nil)" do
      result = FlopParams.build(%{node_ids: []}, multi: [:node_ids])

      refute Map.has_key?(result, "node_ids")
    end

    test "missing key is silently absent from output" do
      result = FlopParams.build(%{}, multi: [:node_ids])

      refute Map.has_key?(result, "node_ids")
    end

    test "multiple multi fields are each handled independently" do
      result =
        FlopParams.build(
          %{node_ids: ["a", "b"], cluster_names: ["prod", "staging"]},
          multi: [:node_ids, :cluster_names]
        )

      assert result["node_ids"] == "a,b"
      assert result["cluster_names"] == "prod,staging"
    end

    test "keys not in :multi are not included even if the value is a list" do
      result = FlopParams.build(%{node_ids: ["a", "b"]}, multi: [])

      refute Map.has_key?(result, "node_ids")
    end
  end

  # ---------------------------------------------------------------------------
  # Combined — pagination + passthrough + ranges + sort
  # ---------------------------------------------------------------------------

  describe "build/2 — full integration" do
    test "produces the documented Flop-shaped map for a realistic call" do
      params = %{
        page: 2,
        page_size: 50,
        status: "healthy",
        name: "prod",
        inserted_at_gte: "2025-01-01T00:00:00Z",
        inserted_at_lte: "2025-02-01T00:00:00Z",
        order_by: "inserted_at,name",
        order_directions: "desc,asc",
        # not in passthrough — must NOT appear
        uninvited: "leak"
      }

      result =
        FlopParams.build(params,
          passthrough: [:status, :name],
          ranges: [:inserted_at, :updated_at]
        )

      assert result == %{
               "page" => 2,
               "page_size" => 50,
               "status" => "healthy",
               "name" => "prod",
               "inserted_at__gte" => "2025-01-01T00:00:00Z",
               "inserted_at__lte" => "2025-02-01T00:00:00Z",
               "order_by" => "inserted_at,name",
               "order_directions" => "desc,asc"
             }
    end
  end
end
