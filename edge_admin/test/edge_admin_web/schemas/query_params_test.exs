# edge_admin/test/edge_admin_web/schemas/query_params_test.exs
defmodule EdgeAdminWeb.Schemas.QueryParamsTest do
  use ExUnit.Case, async: true

  alias EdgeAdminWeb.Schemas.QueryParams
  alias OpenApiSpex.Schema

  # ---------------------------------------------------------------------------
  # pagination/1 — page + page_size keys (parsed by RequestParser; drift here
  # silently breaks every paginated endpoint).
  # ---------------------------------------------------------------------------

  describe "pagination/1" do
    test "returns a keyword list with :page and :page_size keys" do
      params = QueryParams.pagination()

      assert Keyword.keys(params) == [:page, :page_size]
    end

    test "page is an integer ≥ 1, defaulting to 1" do
      params = QueryParams.pagination()
      page = params[:page]

      assert page[:in] == :query
      assert page[:schema] == %Schema{type: :integer, minimum: 1, default: 1}
    end

    test "page_size defaults to 20 with a max of 100" do
      params = QueryParams.pagination()

      assert params[:page_size][:schema] == %Schema{
               type: :integer,
               minimum: 1,
               maximum: 100,
               default: 20
             }
    end

    test "default_page_size and max_page_size are configurable" do
      params = QueryParams.pagination(default_page_size: 50, max_page_size: 500)

      assert params[:page_size][:schema] == %Schema{
               type: :integer,
               minimum: 1,
               maximum: 500,
               default: 50
             }

      assert params[:page_size][:example] == 50
    end
  end

  # ---------------------------------------------------------------------------
  # sort/1 — order_by + order_directions keys (parsed by RequestParser)
  # ---------------------------------------------------------------------------

  describe "sort/1" do
    test "returns :order_by and :order_directions keys" do
      params = QueryParams.sort()

      assert Keyword.keys(params) == [:order_by, :order_directions]
    end

    test "both fields are strings (comma-separated handled by RequestParser)" do
      params = QueryParams.sort()

      assert params[:order_by][:schema] == %Schema{type: :string}
      assert params[:order_directions][:schema] == %Schema{type: :string}
    end

    test "examples default to inserted_at / desc, configurable" do
      defaults = QueryParams.sort()
      assert defaults[:order_by][:example] == "inserted_at"
      assert defaults[:order_directions][:example] == "desc"

      custom = QueryParams.sort(order_by_example: "name", order_directions_example: "asc")
      assert custom[:order_by][:example] == "name"
      assert custom[:order_directions][:example] == "asc"
    end
  end

  # ---------------------------------------------------------------------------
  # Single-key filters — string / enum / boolean / uuid / int
  # ---------------------------------------------------------------------------

  describe "string_filter/2" do
    test "produces {name, [:in, :description, :schema]} with :string schema" do
      assert {:name, opts} = QueryParams.string_filter(:name)

      assert opts[:in] == :query
      assert opts[:schema] == %Schema{type: :string}
      assert opts[:description] =~ "Filter by name"
      assert opts[:description] =~ "wildcard"
    end

    test "description override" do
      {_, opts} = QueryParams.string_filter(:name, description: "custom")
      assert opts[:description] == "custom"
    end
  end

  describe "enum_filter/3" do
    test "constrains the schema to the supplied enum values" do
      {:status, opts} = QueryParams.enum_filter(:status, ["healthy", "unhealthy"])

      assert opts[:schema] == %Schema{type: :string, enum: ["healthy", "unhealthy"]}
    end
  end

  describe "boolean_filter/2" do
    test "produces a :boolean-typed query parameter" do
      {:has_node_limit, opts} = QueryParams.boolean_filter(:has_node_limit)

      assert opts[:schema] == %Schema{type: :boolean}
    end
  end

  describe "uuid_filter/2" do
    test "produces a uuid-formatted :string query parameter" do
      {:command_id, opts} = QueryParams.uuid_filter(:command_id)

      assert opts[:schema] == %Schema{type: :string, format: :uuid}
    end
  end

  describe "int_filter/2" do
    test "produces an :integer-typed parameter, default minimum 0" do
      {:node_count, opts} = QueryParams.int_filter(:node_count)

      assert opts[:schema] == %Schema{type: :integer, minimum: 0}
    end

    test "minimum is configurable" do
      {:port, opts} = QueryParams.int_filter(:port, minimum: 1)

      assert opts[:schema] == %Schema{type: :integer, minimum: 1}
    end
  end

  # ---------------------------------------------------------------------------
  # Range filters — produce `name__gte` AND `name__lte` keys (the suffix
  # convention RequestParser parses).
  # ---------------------------------------------------------------------------

  describe "int_range_filter/2" do
    test "produces both __gte and __lte keys" do
      params = QueryParams.int_range_filter(:node_count)

      assert Keyword.keys(params) == [:node_count__gte, :node_count__lte]
    end

    test "both endpoints are :integer with the same minimum" do
      params = QueryParams.int_range_filter(:node_count, minimum: 5)

      assert params[:node_count__gte][:schema] == %Schema{type: :integer, minimum: 5}
      assert params[:node_count__lte][:schema] == %Schema{type: :integer, minimum: 5}
    end

    test "default minimum is 0" do
      params = QueryParams.int_range_filter(:x)

      assert params[:x__gte][:schema].minimum == 0
      assert params[:x__lte][:schema].minimum == 0
    end
  end

  describe "datetime_range_filter/2" do
    test "produces both __gte and __lte keys" do
      params = QueryParams.datetime_range_filter(:inserted_at)

      assert Keyword.keys(params) == [:inserted_at__gte, :inserted_at__lte]
    end

    test "schema accepts both ISO date-time and date-only (anyOf)" do
      params = QueryParams.datetime_range_filter(:inserted_at)

      schema = params[:inserted_at__gte][:schema]

      assert schema == %Schema{
               anyOf: [
                 %Schema{type: :string, format: :"date-time"},
                 %Schema{type: :string, format: :date}
               ]
             }

      # Both endpoints share the same shape.
      assert params[:inserted_at__lte][:schema] == schema
    end

    test "descriptions document date-only-as-day-boundary semantics" do
      params = QueryParams.datetime_range_filter(:inserted_at)

      assert params[:inserted_at__gte][:description] =~ "start of day"
      assert params[:inserted_at__lte][:description] =~ "end of day"
    end
  end
end
