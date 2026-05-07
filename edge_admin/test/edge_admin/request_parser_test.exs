# edge_admin/test/edge_admin/request_parser_test.exs
defmodule EdgeAdmin.RequestParserTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.RequestParser

  # ---------------------------------------------------------------------------
  # parse/1 — pagination defaults
  # ---------------------------------------------------------------------------

  describe "parse/1 — pagination defaults" do
    test "empty params returns default page and page_size" do
      result = RequestParser.parse(%{})
      assert result[:page] == 1
      assert result[:page_size] == 20
    end

    test "no filters key when params is empty" do
      result = RequestParser.parse(%{})
      assert result[:filters] == [] or not Map.has_key?(result, :filters)
    end

    test "no order_by key when not provided" do
      result = RequestParser.parse(%{})
      refute Map.has_key?(result, :order_by)
    end

    test "no order_directions key when not provided" do
      result = RequestParser.parse(%{})
      refute Map.has_key?(result, :order_directions)
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — page parsing
  # ---------------------------------------------------------------------------

  describe "parse/1 — page parsing" do
    test "parses page from integer" do
      result = RequestParser.parse(%{"page" => 5})
      assert result[:page] == 5
    end

    test "atom key page is normalized and parsed" do
      result = RequestParser.parse(%{page: 3})
      assert result[:page] == 3
    end

    test "invalid page (zero) defaults to 1" do
      result = RequestParser.parse(%{"page" => 0})
      assert result[:page] == 1
    end

    test "negative page defaults to 1" do
      result = RequestParser.parse(%{"page" => -1})
      assert result[:page] == 1
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — page_size parsing
  # ---------------------------------------------------------------------------

  describe "parse/1 — page_size parsing" do
    test "parses page_size from integer" do
      result = RequestParser.parse(%{"page_size" => 10})
      assert result[:page_size] == 10
    end

    test "atom key page_size is normalized and parsed" do
      result = RequestParser.parse(%{page_size: 50})
      assert result[:page_size] == 50
    end

    test "zero page_size defaults to 20" do
      result = RequestParser.parse(%{"page_size" => 0})
      assert result[:page_size] == 20
    end

    test "boundary: page_size of 1 is accepted" do
      result = RequestParser.parse(%{"page_size" => 1})
      assert result[:page_size] == 1
    end

    test "boundary: page_size of 100 is accepted" do
      result = RequestParser.parse(%{"page_size" => 100})
      assert result[:page_size] == 100
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — order_by parsing
  # ---------------------------------------------------------------------------

  describe "parse/1 — order_by parsing" do
    test "parses single order_by field" do
      result = RequestParser.parse(%{"order_by" => "inserted_at"})
      assert result[:order_by] == [:inserted_at]
    end

    test "parses multiple order_by fields comma-separated" do
      result = RequestParser.parse(%{"order_by" => "inserted_at,updated_at"})
      assert result[:order_by] == [:inserted_at, :updated_at]
    end

    test "trims whitespace from order_by fields" do
      result = RequestParser.parse(%{"order_by" => "inserted_at, updated_at"})
      assert result[:order_by] == [:inserted_at, :updated_at]
    end

    test "unknown field is silently dropped from order_by" do
      result = RequestParser.parse(%{"order_by" => "inserted_at,totally_nonexistent_xyz_field"})
      assert result[:order_by] == [:inserted_at]
    end

    test "order_by not in result when not provided" do
      result = RequestParser.parse(%{})
      refute Map.has_key?(result, :order_by)
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — order_directions parsing
  # ---------------------------------------------------------------------------

  describe "parse/1 — order_directions parsing" do
    test "parses asc direction" do
      result = RequestParser.parse(%{"order_directions" => "asc"})
      assert result[:order_directions] == [:asc]
    end

    test "parses desc direction" do
      result = RequestParser.parse(%{"order_directions" => "desc"})
      assert result[:order_directions] == [:desc]
    end

    test "parses multiple directions comma-separated" do
      result = RequestParser.parse(%{"order_directions" => "desc,asc"})
      assert result[:order_directions] == [:desc, :asc]
    end

    test "invalid direction is silently dropped" do
      result = RequestParser.parse(%{"order_directions" => "desc,sideways"})
      assert result[:order_directions] == [:desc]
    end

    test "all invalid directions → order_directions key omitted (compact removes empty list)" do
      result = RequestParser.parse(%{"order_directions" => "sideways,upward"})
      refute Map.has_key?(result, :order_directions)
    end

    test "order_directions not in result when not provided" do
      result = RequestParser.parse(%{})
      refute Map.has_key?(result, :order_directions)
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — reserved params are not treated as filters
  # ---------------------------------------------------------------------------

  describe "parse/1 — reserved params excluded from filters" do
    test "page is not in filters" do
      result = RequestParser.parse(%{"page" => 2})
      filters = result[:filters] || []
      refute Enum.any?(filters, &(&1.field == :page))
    end

    test "page_size is not in filters" do
      result = RequestParser.parse(%{"page_size" => 10})
      filters = result[:filters] || []
      refute Enum.any?(filters, &(&1.field == :page_size))
    end

    test "order_by is not in filters" do
      result = RequestParser.parse(%{"order_by" => "inserted_at"})
      filters = result[:filters] || []
      refute Enum.any?(filters, &(&1.field == :order_by))
    end

    test "order_directions is not in filters" do
      result = RequestParser.parse(%{"order_directions" => "asc"})
      filters = result[:filters] || []
      refute Enum.any?(filters, &(&1.field == :order_directions))
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — exact match filters
  # ---------------------------------------------------------------------------

  describe "parse/1 — exact match filters" do
    test "plain string value produces == filter" do
      result = RequestParser.parse(%{"status" => "active"})
      assert_filter(result, :status, :==, "active")
    end

    test "boolean true produces == filter with true" do
      result = RequestParser.parse(%{"self_update_enabled" => true})
      assert_filter(result, :self_update_enabled, :==, true)
    end

    test "boolean false produces == filter with false" do
      result = RequestParser.parse(%{"self_update_enabled" => false})
      assert_filter(result, :self_update_enabled, :==, false)
    end

    test "unknown field is silently dropped from filters" do
      result = RequestParser.parse(%{"totally_nonexistent_xyz_field" => "value"})
      filters = result[:filters] || []
      assert filters == []
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — wildcard / ilike filters
  # ---------------------------------------------------------------------------

  describe "parse/1 — wildcard (ilike) filters" do
    test "trailing * produces starts-with ilike" do
      result = RequestParser.parse(%{"name" => "prod*"})
      assert_filter(result, :name, :ilike, "prod%")
    end

    test "leading * produces ends-with ilike" do
      result = RequestParser.parse(%{"name" => "*prod"})
      assert_filter(result, :name, :ilike, "%prod")
    end

    test "both * produces contains ilike" do
      result = RequestParser.parse(%{"name" => "*prod*"})
      assert_filter(result, :name, :ilike, "%prod%")
    end

    test "* in middle is replaced with %" do
      result = RequestParser.parse(%{"name" => "pr*d"})
      assert_filter(result, :name, :ilike, "pr%d")
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — IN operator (comma-separated values)
  # ---------------------------------------------------------------------------

  describe "parse/1 — IN filters" do
    test "comma-separated value produces :in filter with list" do
      result = RequestParser.parse(%{"status" => "pending,completed"})
      assert_filter(result, :status, :in, ["pending", "completed"])
    end

    test "values are trimmed of whitespace" do
      result = RequestParser.parse(%{"status" => "pending, completed"})
      assert_filter(result, :status, :in, ["pending", "completed"])
    end

    test "explicit __in suffix also produces :in filter" do
      result = RequestParser.parse(%{"status__in" => "pending,completed"})
      assert_filter(result, :status, :in, "pending,completed")
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — range / comparison operators (__gte, __gt, etc.)
  # ---------------------------------------------------------------------------

  describe "parse/1 — range operator filters" do
    test "__gte with full datetime string passes through unchanged" do
      result = RequestParser.parse(%{"inserted_at__gte" => "2025-01-01T00:00:00Z"})
      assert_filter(result, :inserted_at, :>=, "2025-01-01T00:00:00Z")
    end

    test "__gte with %Date{} struct produces ISO string filter" do
      result = RequestParser.parse(%{"inserted_at__gte" => ~D[2025-01-01]})
      assert_filter(result, :inserted_at, :>=, "2025-01-01")
    end

    test "__gte with %DateTime{} struct produces ISO string filter" do
      result = RequestParser.parse(%{"inserted_at__gte" => ~U[2025-01-01 00:00:00Z]})
      assert_filter(result, :inserted_at, :>=, "2025-01-01T00:00:00Z")
    end

    test "__lte with full datetime string passes through unchanged" do
      result = RequestParser.parse(%{"inserted_at__lte" => "2025-12-31T23:59:59Z"})
      assert_filter(result, :inserted_at, :<=, "2025-12-31T23:59:59Z")
    end

    test "__lte with %Date{} struct produces ISO string filter" do
      result = RequestParser.parse(%{"inserted_at__lte" => ~D[2025-12-31]})
      assert_filter(result, :inserted_at, :<=, "2025-12-31")
    end

    test "__ne produces != filter" do
      result = RequestParser.parse(%{"status__ne" => "pending"})
      assert_filter(result, :status, :!=, "pending")
    end

    test "__eq produces == filter" do
      result = RequestParser.parse(%{"status__eq" => "active"})
      assert_filter(result, :status, :==, "active")
    end

    test "__ilike produces :ilike filter" do
      result = RequestParser.parse(%{"name__ilike" => "%prod%"})
      assert_filter(result, :name, :ilike, "%prod%")
    end

    test "__like produces :like filter" do
      result = RequestParser.parse(%{"name__like" => "%prod%"})
      assert_filter(result, :name, :like, "%prod%")
    end

    test "__null=true produces :empty filter" do
      result = RequestParser.parse(%{"node_limit__null" => "true"})
      assert_filter(result, :node_limit, :empty, true)
    end

    test "__null=false produces :not_empty filter" do
      result = RequestParser.parse(%{"node_limit__null" => "false"})
      assert_filter(result, :node_limit, :not_empty, true)
    end

    test "unknown operator suffix is silently dropped" do
      result = RequestParser.parse(%{"status__fuzzy" => "active"})
      filters = result[:filters] || []
      assert filters == []
    end

    test "__gte with unknown field is silently dropped" do
      result = RequestParser.parse(%{"totally_nonexistent_xyz_field__gte" => "2025-01-01"})
      filters = result[:filters] || []
      assert filters == []
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — atom key normalization
  # ---------------------------------------------------------------------------

  describe "parse/1 — atom key normalization" do
    test "atom key params are normalized to strings and parsed" do
      result = RequestParser.parse(%{status: "active", page: 2, page_size: 50})
      assert result[:page] == 2
      assert result[:page_size] == 50
      assert_filter(result, :status, :==, "active")
    end

    test "atom key order_by is parsed" do
      result = RequestParser.parse(%{order_by: "inserted_at", order_directions: "desc"})
      assert result[:order_by] == [:inserted_at]
      assert result[:order_directions] == [:desc]
    end

    test "mixed atom and string keys both work" do
      result = RequestParser.parse(%{"status" => "healthy", page: 3})
      assert result[:page] == 3
      assert_filter(result, :status, :==, "healthy")
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — multiple filters combined
  # ---------------------------------------------------------------------------

  describe "parse/1 — multiple filters" do
    test "multiple params produce multiple filters" do
      result =
        RequestParser.parse(%{
          "status" => "active",
          "inserted_at__gte" => "2025-01-01T00:00:00Z"
        })

      filters = result[:filters]
      assert length(filters) == 2
      assert Enum.any?(filters, &(&1.field == :status and &1.op == :== and &1.value == "active"))

      assert Enum.any?(
               filters,
               &(&1.field == :inserted_at and &1.op == :>= and
                   &1.value == "2025-01-01T00:00:00Z")
             )
    end

    test "mix of filters and pagination" do
      result =
        RequestParser.parse(%{
          "status" => "healthy",
          "page" => 2,
          "page_size" => 50,
          "order_by" => "inserted_at",
          "order_directions" => "desc"
        })

      assert result[:page] == 2
      assert result[:page_size] == 50
      assert result[:order_by] == [:inserted_at]
      assert result[:order_directions] == [:desc]
      assert_filter(result, :status, :==, "healthy")
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — compact (nil/empty values omitted)
  # ---------------------------------------------------------------------------

  describe "parse/1 — compact removes nil and empty" do
    test "order_by not present when nil (not provided)" do
      result = RequestParser.parse(%{"status" => "active"})
      refute Map.has_key?(result, :order_by)
    end

    test "order_directions not present when nil (not provided)" do
      result = RequestParser.parse(%{"status" => "active"})
      refute Map.has_key?(result, :order_directions)
    end

    test "filters key omitted when no filters parsed" do
      result = RequestParser.parse(%{"page" => 1, "page_size" => 20})
      filters = result[:filters] || []
      assert filters == []
    end
  end

  # ---------------------------------------------------------------------------
  # split_ilike_filters/2 — splits ilike filters out so callers can apply them
  # as raw Ecto clauses without Flop's wildcard escaping.
  # ---------------------------------------------------------------------------

  describe "split_ilike_filters/2" do
    test "extracts ilike filters for the listed fields, leaves others untouched" do
      flop_params = %{
        filters: [
          %{field: :name, op: :ilike, value: "prod%"},
          %{field: :version, op: :==, value: "1.0"},
          %{field: :description, op: :ilike, value: "%edge%"}
        ],
        page: 1,
        page_size: 20
      }

      {ilike, rest} = RequestParser.split_ilike_filters(flop_params, [:name])

      assert ilike == [%{field: :name, op: :ilike, value: "prod%"}]

      assert rest.filters == [
               %{field: :version, op: :==, value: "1.0"},
               %{field: :description, op: :ilike, value: "%edge%"}
             ]

      # Other keys are preserved.
      assert rest.page == 1
      assert rest.page_size == 20
    end

    test "extracts multiple matching ilike filters at once" do
      flop_params = %{
        filters: [
          %{field: :name, op: :ilike, value: "prod%"},
          %{field: :version, op: :ilike, value: "1.%"},
          %{field: :status, op: :==, value: "active"}
        ]
      }

      {ilike, rest} = RequestParser.split_ilike_filters(flop_params, [:name, :version])

      assert length(ilike) == 2
      assert %{field: :name, op: :ilike, value: "prod%"} in ilike
      assert %{field: :version, op: :ilike, value: "1.%"} in ilike

      assert rest.filters == [%{field: :status, op: :==, value: "active"}]
    end

    test "ignores ilike filters for fields not in the allow-list" do
      flop_params = %{
        filters: [%{field: :name, op: :ilike, value: "prod%"}]
      }

      {ilike, rest} = RequestParser.split_ilike_filters(flop_params, [:other_field])

      assert ilike == []
      assert rest.filters == [%{field: :name, op: :ilike, value: "prod%"}]
    end

    test "ignores non-ilike filters even when the field is in the allow-list" do
      # Critical: only :ilike ops are extracted — :== or :in on the same field
      # must stay in Flop's hands.
      flop_params = %{
        filters: [
          %{field: :name, op: :==, value: "prod"},
          %{field: :name, op: :in, value: ["a", "b"]}
        ]
      }

      {ilike, rest} = RequestParser.split_ilike_filters(flop_params, [:name])

      assert ilike == []
      assert length(rest.filters) == 2
    end

    test "missing :filters key is treated as empty list" do
      flop_params = %{page: 1, page_size: 20}

      {ilike, rest} = RequestParser.split_ilike_filters(flop_params, [:name])

      assert ilike == []
      # split_ilike_filters always sets :filters to whatever remains, so the
      # output map gains the key even when the input didn't have it.
      assert rest.filters == []
      assert rest.page == 1
    end

    test "empty fields list extracts nothing" do
      flop_params = %{
        filters: [%{field: :name, op: :ilike, value: "prod%"}]
      }

      {ilike, rest} = RequestParser.split_ilike_filters(flop_params, [])

      assert ilike == []
      assert rest.filters == [%{field: :name, op: :ilike, value: "prod%"}]
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp assert_filter(result, field, op, value) do
    filters = result[:filters] || []

    assert Enum.any?(filters, fn f ->
             f.field == field and f.op == op and f.value == value
           end),
           "expected filter %{field: #{inspect(field)}, op: #{inspect(op)}, value: #{inspect(value)}} in #{inspect(filters)}"
  end
end
