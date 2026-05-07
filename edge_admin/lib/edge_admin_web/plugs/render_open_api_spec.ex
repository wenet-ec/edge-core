# edge_admin/lib/edge_admin_web/plugs/render_open_api_spec.ex
defmodule EdgeAdminWeb.Plugs.RenderOpenApiSpec do
  @moduledoc """
  Renders the OpenAPI spec with Internal.* tagged paths removed.

  OpenApiSpec (full spec) is kept intact for CastAndValidate operationId lookup.
  This plug filters on the fly before rendering so SwaggerUI/ReDoc only show
  public endpoints.
  """

  @behaviour Plug

  @internal_tag_prefix "Internal."

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    json =
      EdgeAdminWeb.OpenApiSpec.spec()
      |> filter_internal_paths()
      |> filter_internal_schemas()
      |> OpenApiSpex.OpenApi.to_map()
      |> sort_paths_in_map()
      |> Jason.encode!()

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, json)
  end

  # Preferred HTTP verb order within a path item: create → list/get → update → delete.
  @verb_order ~w(post get put patch delete head options trace)

  @doc false
  # Public for unit testing. Jason.encode! on a plain map uses hash order. By
  # converting paths and their verb maps to Jason.OrderedObject, we preserve
  # both orders through to the wire.
  @spec sort_paths_in_map(map()) :: map()
  def sort_paths_in_map(%{"paths" => paths} = spec_map) when is_map(paths) do
    ordered_paths =
      paths
      |> Enum.sort_by(fn {path, _} ->
        Map.get(EdgeAdminWeb.OpenApiSpec.paths_order_index(), path, 999_999)
      end)
      |> Enum.map(fn {path, path_item} -> {path, sort_verbs(path_item)} end)

    %{spec_map | "paths" => Jason.OrderedObject.new(ordered_paths)}
  end

  def sort_paths_in_map(spec_map), do: spec_map

  @doc false
  # Public for unit testing. Reorders the HTTP verbs in a path item to the
  # documented order: post → get → put → patch → delete → head → options → trace.
  @spec sort_verbs(map()) :: Jason.OrderedObject.t()
  def sort_verbs(path_item) when is_map(path_item) do
    verb_index = @verb_order |> Enum.with_index() |> Map.new()

    ordered =
      Enum.sort_by(path_item, fn {verb, _} -> Map.get(verb_index, verb, 999) end)

    Jason.OrderedObject.new(ordered)
  end

  @doc false
  # Public for unit testing. Drops paths whose every operation is tagged
  # exclusively with `Internal.*`. Mixed paths (some operations public, some
  # internal) stay — only fully-internal paths are stripped. This is the
  # security-adjacent contract: regression here leaks internal endpoints into
  # public Swagger / ReDoc.
  @spec filter_internal_paths(OpenApiSpex.OpenApi.t()) :: OpenApiSpex.OpenApi.t()
  def filter_internal_paths(%OpenApiSpex.OpenApi{paths: paths} = spec) do
    filtered =
      Map.reject(paths, fn {_path, path_item} ->
        path_item
        |> Map.from_struct()
        |> Map.values()
        |> Enum.filter(&is_struct/1)
        |> Enum.all?(fn operation ->
          case Map.get(operation, :tags) do
            tags when is_list(tags) and tags != [] ->
              Enum.all?(tags, &String.starts_with?(&1, @internal_tag_prefix))

            _ ->
              false
          end
        end)
      end)

    %{spec | paths: filtered}
  end

  @doc false
  # Public for unit testing. Drops component schemas whose name starts with
  # `Internal.`, so they aren't referenced from the published spec.
  @spec filter_internal_schemas(OpenApiSpex.OpenApi.t()) :: OpenApiSpex.OpenApi.t()
  def filter_internal_schemas(%OpenApiSpex.OpenApi{components: components} = spec) do
    filtered_schemas =
      Map.reject(components.schemas, fn {key, _} ->
        String.starts_with?(to_string(key), @internal_tag_prefix)
      end)

    %{spec | components: %{components | schemas: filtered_schemas}}
  end
end
