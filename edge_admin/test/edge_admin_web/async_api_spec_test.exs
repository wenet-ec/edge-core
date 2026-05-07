# edge_admin/test/edge_admin_web/async_api_spec_test.exs
defmodule EdgeAdminWeb.AsyncApiSpecTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Catalog
  alias EdgeAdminWeb.AsyncApiSpec

  # The whole point of this file: pin the cross-module contract that every
  # event type in `Catalog.all_event_types/0` has a corresponding entry in
  # `AsyncApiSpec.@message_specs`. Drift here used to break silently — the
  # spec rendered fine until a request hit the missing entry, then crashed
  # with `Map.fetch!`. The test catches the missing entry at compile time.

  describe "spec/0" do
    test "builds without raising" do
      # If a new event type is added to the catalog without a corresponding
      # @message_specs entry, the messages/0 builder calls Map.fetch! and
      # crashes here. That's the regression this test exists to catch.
      assert is_map(AsyncApiSpec.spec())
    end

    test "covers every catalog event type with an AsyncAPI message" do
      messages = AsyncApiSpec.spec()["components"]["messages"]

      # The message ref names are derived from the event type (catalog ->
      # CamelCase address -> ref). Rather than reverse-engineer the ref
      # naming here, just assert the count matches: one message per catalog
      # event type. If counts diverge, the messages/0 builder either skipped
      # a type or grew an extra entry — both are bugs.
      assert map_size(messages) == length(Catalog.all_event_types())
    end

    test "every message references the shared CloudEvents Envelope schema" do
      messages = AsyncApiSpec.spec()["components"]["messages"]

      for {ref, message} <- messages do
        assert message["payload"]["$ref"] == "#/components/schemas/Envelope",
               "message #{inspect(ref)} should reference #/components/schemas/Envelope"
      end
    end

    test "every message has a non-empty summary (sourced from Catalog.description/1)" do
      messages = AsyncApiSpec.spec()["components"]["messages"]

      for {ref, message} <- messages do
        assert is_binary(message["summary"]) and message["summary"] != "",
               "message #{inspect(ref)} should have a non-empty summary"
      end
    end

    test "every message carries an example with the matching event type in the envelope" do
      messages = AsyncApiSpec.spec()["components"]["messages"]
      catalog_types = MapSet.new(Catalog.all_event_types())

      seen_types =
        for {_ref, message} <- messages,
            example <- message["examples"],
            into: MapSet.new() do
          example["payload"]["type"]
        end

      # Every example's type matches a catalog event type.
      assert MapSet.subset?(seen_types, catalog_types),
             "examples reference types not in the catalog: " <>
               inspect(MapSet.difference(seen_types, catalog_types))

      # Every catalog type appears in at least one example.
      assert MapSet.equal?(seen_types, catalog_types),
             "catalog types missing examples: " <>
               inspect(MapSet.difference(catalog_types, seen_types))
    end

    test "top-level shape matches the AsyncAPI 3.1.0 contract" do
      spec = AsyncApiSpec.spec()

      assert spec["asyncapi"] == "3.1.0"
      assert spec["defaultContentType"] == "application/json"
      assert is_map(spec["info"])
      assert is_map(spec["servers"])
      assert is_map(spec["channels"])
      assert is_map(spec["operations"])
      assert is_map(spec["components"])

      assert is_map(spec["components"]["messages"])
      assert is_map(spec["components"]["schemas"])
      assert is_map(spec["components"]["securitySchemes"])
    end
  end
end
