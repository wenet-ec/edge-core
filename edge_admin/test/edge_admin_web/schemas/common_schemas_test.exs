# edge_admin/test/edge_admin_web/schemas/common_schemas_test.exs
defmodule EdgeAdminWeb.Schemas.CommonSchemasTest do
  use ExUnit.Case, async: true

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas.MetaSchema
  alias EdgeAdminWeb.Schemas.CommonSchemas.PaginatedMetaSchema
  alias OpenApiSpex.Schema

  # The two builders here define the canonical envelope shape every REST
  # response uses. Drift here breaks every client that decodes responses.

  defmodule FakeDataSchema do
    @moduledoc false
    # Stand-in for any concrete *Response schema — the builder doesn't care
    # about the shape, only that it's referenced as the data field's items.
  end

  # ---------------------------------------------------------------------------
  # paginated_response/3 — collection envelope: %{data: [...], meta: meta}
  # ---------------------------------------------------------------------------

  describe "paginated_response/3" do
    test "produces the documented title, description, type" do
      result = CommonSchemas.paginated_response(FakeDataSchema, "NodePaginated", "Paginated nodes")

      assert result.title == "NodePaginated"
      assert result.description == "Paginated nodes"
      assert result.type == :object
    end

    test "data is an array of the supplied data_schema" do
      result = CommonSchemas.paginated_response(FakeDataSchema, "T", "D")

      assert result.properties.data == %Schema{type: :array, items: FakeDataSchema}
    end

    test "meta is the shared PaginatedMetaSchema (with totals + page info)" do
      result = CommonSchemas.paginated_response(FakeDataSchema, "T", "D")

      assert result.properties.meta == PaginatedMetaSchema
    end

    test "data and meta are both required" do
      result = CommonSchemas.paginated_response(FakeDataSchema, "T", "D")

      assert Enum.sort(result.required) == [:data, :meta]
    end

    test "PaginatedMetaSchema is distinct from MetaSchema (collection vs single)" do
      # The whole point of having two — paginated has more fields. Pin the
      # distinction so a careless 'simplification' doesn't merge them.
      refute PaginatedMetaSchema == MetaSchema
    end
  end

  # ---------------------------------------------------------------------------
  # single_response/3 — single-resource envelope: %{data: <obj>, meta: meta}
  # ---------------------------------------------------------------------------

  describe "single_response/3" do
    test "produces the documented title, description, type" do
      result = CommonSchemas.single_response(FakeDataSchema, "NodeSingle", "Single node")

      assert result.title == "NodeSingle"
      assert result.description == "Single node"
      assert result.type == :object
    end

    test "data is the supplied data_schema directly (NOT wrapped in an array)" do
      # Critical contract distinction from paginated_response: the data field
      # is the schema itself, not %{type: :array, items: schema}.
      result = CommonSchemas.single_response(FakeDataSchema, "T", "D")

      assert result.properties.data == FakeDataSchema
    end

    test "meta is the shared MetaSchema (no pagination fields)" do
      result = CommonSchemas.single_response(FakeDataSchema, "T", "D")

      assert result.properties.meta == MetaSchema
    end

    test "data and meta are both required" do
      result = CommonSchemas.single_response(FakeDataSchema, "T", "D")

      assert Enum.sort(result.required) == [:data, :meta]
    end
  end
end
