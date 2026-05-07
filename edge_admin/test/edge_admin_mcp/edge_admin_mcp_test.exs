# edge_admin/test/edge_admin_mcp/edge_admin_mcp_test.exs
defmodule EdgeAdminMcpTest do
  use ExUnit.Case, async: true

  defp meta(overrides \\ []) do
    struct(
      Flop.Meta,
      Keyword.merge(
        [
          current_page: 1,
          page_size: 20,
          total_count: 0,
          total_pages: 0,
          has_next_page?: false,
          has_previous_page?: false
        ],
        overrides
      )
    )
  end

  # ---------------------------------------------------------------------------
  # paginated/3 — canonical MCP list envelope. Mirrors REST's
  # ResponseEnvelope pagination renames so the two surfaces emit the same shape.
  # ---------------------------------------------------------------------------

  describe "paginated/3" do
    test "wraps items in :items and exposes the documented page fields" do
      result = EdgeAdminMcp.paginated([%{id: "a"}, %{id: "b"}], meta(total_count: 2))

      assert result |> Map.keys() |> Enum.sort() ==
               [:has_next, :has_prev, :items, :page, :page_size, :total_count, :total_pages]

      assert result.items == [%{id: "a"}, %{id: "b"}]
    end

    test "renames Flop.Meta fields to MCP-facing names" do
      result =
        EdgeAdminMcp.paginated(
          [],
          meta(
            current_page: 3,
            page_size: 50,
            total_count: 200,
            total_pages: 4,
            has_next_page?: true,
            has_previous_page?: true
          )
        )

      # current_page → page
      assert result.page == 3
      refute Map.has_key?(result, :current_page)

      # has_next_page? → has_next, has_previous_page? → has_prev
      assert result.has_next == true
      assert result.has_prev == true
      refute Map.has_key?(result, :has_next_page?)
      refute Map.has_key?(result, :has_previous_page?)

      # passthrough fields
      assert result.page_size == 50
      assert result.total_count == 200
      assert result.total_pages == 4
    end

    test "applies the mapper to each item" do
      result =
        EdgeAdminMcp.paginated(
          [%{name: "alice"}, %{name: "bob"}],
          meta(total_count: 2),
          fn item -> %{username: item.name} end
        )

      assert result.items == [%{username: "alice"}, %{username: "bob"}]
    end

    test "default mapper is identity" do
      items = [%{a: 1}, %{a: 2}]
      assert EdgeAdminMcp.paginated(items, meta(total_count: 2)).items == items
    end

    test "empty list yields empty :items" do
      result = EdgeAdminMcp.paginated([], meta())
      assert result.items == []
      assert result.total_count == 0
      assert result.has_next == false
      assert result.has_prev == false
    end

    test "false flags are preserved (not coerced to nil)" do
      result =
        EdgeAdminMcp.paginated([], meta(has_next_page?: false, has_previous_page?: false))

      assert result.has_next === false
      assert result.has_prev === false
    end
  end
end
