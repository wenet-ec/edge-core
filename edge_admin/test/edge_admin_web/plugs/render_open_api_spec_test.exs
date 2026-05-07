# edge_admin/test/edge_admin_web/plugs/render_open_api_spec_test.exs
defmodule EdgeAdminWeb.Plugs.RenderOpenApiSpecTest do
  use ExUnit.Case, async: true

  alias EdgeAdminWeb.Plugs.RenderOpenApiSpec
  alias OpenApiSpex.Components
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Operation
  alias OpenApiSpex.PathItem

  defp op(tags) do
    %Operation{
      tags: tags,
      operationId: "op-#{Enum.join(tags, "-")}",
      responses: %{}
    }
  end

  defp path_item(operations) do
    Enum.reduce(operations, %PathItem{}, fn {verb, op}, acc ->
      Map.put(acc, verb, op)
    end)
  end

  # ---------------------------------------------------------------------------
  # filter_internal_paths/1 — security-adjacent: prevents internal endpoints
  # from leaking into public Swagger / ReDoc.
  # ---------------------------------------------------------------------------

  describe "filter_internal_paths/1" do
    test "drops paths whose every operation is exclusively Internal.*-tagged" do
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{
          "/api/v1/public" => path_item(get: op(["Public"])),
          "/api/v1/internal" => path_item(get: op(["Internal.Admins"]))
        }
      }

      result = RenderOpenApiSpec.filter_internal_paths(spec)

      assert Map.has_key?(result.paths, "/api/v1/public")
      refute Map.has_key?(result.paths, "/api/v1/internal")
    end

    test "drops paths where every verb's operation is internal (multi-verb internal path)" do
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{
          "/api/v1/internal-mixed-verbs" => path_item(get: op(["Internal.Admins"]), post: op(["Internal.Admins"]))
        }
      }

      result = RenderOpenApiSpec.filter_internal_paths(spec)

      assert result.paths == %{}
    end

    test "keeps mixed paths (some operations public, some internal)" do
      # Critical contract: a path with both public and internal operations stays
      # in the published spec — the public verbs belong there.
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{
          "/api/v1/mixed" => path_item(get: op(["Public"]), post: op(["Internal.Admins"]))
        }
      }

      result = RenderOpenApiSpec.filter_internal_paths(spec)

      assert Map.has_key?(result.paths, "/api/v1/mixed")
    end

    test "keeps paths with a multi-tag operation that mixes Internal.* with public tags" do
      # Each operation's tags are AND-checked: the operation is only 'internal'
      # if EVERY one of its tags starts with Internal.*. A mixed-tag op is
      # treated as public.
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{
          "/api/v1/multi-tag" => path_item(get: op(["Public", "Internal.Admins"]))
        }
      }

      result = RenderOpenApiSpec.filter_internal_paths(spec)

      assert Map.has_key?(result.paths, "/api/v1/multi-tag")
    end

    test "keeps paths whose operations are tagless (defensive — tagless = public)" do
      # An operation with no tags is treated as public. This means an untagged
      # but conceptually-internal endpoint will leak — but that's a tagging bug,
      # not a filter bug.
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{
          "/api/v1/tagless" => path_item(get: op([]))
        }
      }

      result = RenderOpenApiSpec.filter_internal_paths(spec)

      assert Map.has_key?(result.paths, "/api/v1/tagless")
    end

    test "preserves the rest of the spec (info, components, etc.) unchanged" do
      info = %OpenApiSpex.Info{title: "Edge Admin", version: "0.1.0"}

      spec = %OpenApi{
        info: info,
        paths: %{"/api/v1/internal" => path_item(get: op(["Internal.Admins"]))},
        components: %Components{schemas: %{"Public" => %{}}}
      }

      result = RenderOpenApiSpec.filter_internal_paths(spec)

      assert result.info == info
      assert result.components.schemas == %{"Public" => %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # filter_internal_schemas/1
  # ---------------------------------------------------------------------------

  describe "filter_internal_schemas/1" do
    test "drops component schemas whose key starts with 'Internal.'" do
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{},
        components: %Components{
          schemas: %{
            "Public.User" => %{type: "object"},
            "Internal.AdminCluster" => %{type: "object"},
            "Public.Cluster" => %{type: "object"}
          }
        }
      }

      result = RenderOpenApiSpec.filter_internal_schemas(spec)

      keys = result.components.schemas |> Map.keys() |> Enum.sort()
      assert keys == ["Public.Cluster", "Public.User"]
    end

    test "handles atom-keyed schemas (to_string converts before matching)" do
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{},
        components: %Components{
          schemas: %{
            "Public" => %{},
            :"Internal.Foo" => %{}
          }
        }
      }

      result = RenderOpenApiSpec.filter_internal_schemas(spec)

      assert Map.has_key?(result.components.schemas, "Public")
      refute Map.has_key?(result.components.schemas, :"Internal.Foo")
    end

    test "leaves the rest of the spec unchanged" do
      spec = %OpenApi{
        info: %OpenApiSpex.Info{title: "t", version: "1"},
        paths: %{"/x" => path_item(get: op(["Public"]))},
        components: %Components{schemas: %{"Internal.Drop" => %{}}}
      }

      result = RenderOpenApiSpec.filter_internal_schemas(spec)

      assert Map.has_key?(result.paths, "/x")
    end
  end

  # ---------------------------------------------------------------------------
  # sort_verbs/1 — post → get → put → patch → delete → head → options → trace
  # ---------------------------------------------------------------------------

  describe "sort_verbs/1" do
    test "reorders verbs to the documented order" do
      path_item = %{
        "delete" => :d,
        "get" => :g,
        "post" => :p,
        "patch" => :pa
      }

      result = RenderOpenApiSpec.sort_verbs(path_item)

      # Jason.OrderedObject keeps insertion order in :values — pull the keys
      # in iteration order to verify.
      assert Enum.map(result.values, fn {k, _} -> k end) == ~w(post get patch delete)
    end

    test "unrecognised verb keys land at the end" do
      path_item = %{"x-custom" => :x, "get" => :g, "post" => :p}

      result = RenderOpenApiSpec.sort_verbs(path_item)

      keys = Enum.map(result.values, fn {k, _} -> k end)
      assert keys == ~w(post get x-custom)
    end

    test "single-verb path items round-trip cleanly" do
      result = RenderOpenApiSpec.sort_verbs(%{"get" => :g})
      assert result.values == [{"get", :g}]
    end
  end

  # ---------------------------------------------------------------------------
  # sort_paths_in_map/1
  # ---------------------------------------------------------------------------

  describe "sort_paths_in_map/1" do
    test "orders paths per OpenApiSpec.paths_order_index/0" do
      # Build a spec_map (post-OpenApiSpex.OpenApi.to_map) with paths in
      # arbitrary order — order should match the catalog after sorting.
      spec_map = %{
        "paths" => %{
          # Catalog has "/api/v1/clusters" before "/api/v1/admins/me", but
          # the catalog actually orders /admins/me first (line 18 of
          # OpenApiSpec) — confirm sort respects catalog order.
          "/api/v1/clusters" => %{"get" => :a},
          "/api/v1/admins/me" => %{"get" => :b}
        }
      }

      result = RenderOpenApiSpec.sort_paths_in_map(spec_map)

      paths = result["paths"]
      keys = Enum.map(paths.values, fn {k, _} -> k end)

      # /api/v1/admins/me has lower index in the catalog → comes first.
      assert keys == ["/api/v1/admins/me", "/api/v1/clusters"]
    end

    test "paths not in the catalog are appended at the end" do
      spec_map = %{
        "paths" => %{
          "/api/v1/clusters" => %{"get" => :a},
          "/api/v1/never-heard-of-this" => %{"get" => :z}
        }
      }

      result = RenderOpenApiSpec.sort_paths_in_map(spec_map)

      keys = Enum.map(result["paths"].values, fn {k, _} -> k end)

      assert keys == ["/api/v1/clusters", "/api/v1/never-heard-of-this"]
    end

    test "verbs within each path are sorted too" do
      spec_map = %{
        "paths" => %{
          "/api/v1/clusters" => %{"delete" => :d, "post" => :p, "get" => :g}
        }
      }

      result = RenderOpenApiSpec.sort_paths_in_map(spec_map)

      [{_, path_item}] = result["paths"].values
      verb_keys = Enum.map(path_item.values, fn {k, _} -> k end)
      assert verb_keys == ~w(post get delete)
    end

    test "passes through spec_maps without 'paths' key (defensive no-op)" do
      assert RenderOpenApiSpec.sort_paths_in_map(%{"info" => %{}}) == %{"info" => %{}}
    end

    test "passes through when 'paths' is not a map (e.g. already serialized)" do
      assert RenderOpenApiSpec.sort_paths_in_map(%{"paths" => "string"}) == %{
               "paths" => "string"
             }
    end
  end
end
