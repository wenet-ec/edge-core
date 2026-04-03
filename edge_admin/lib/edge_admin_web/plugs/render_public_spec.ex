# edge_admin/lib/edge_admin_web/plugs/render_public_spec.ex
defmodule EdgeAdminWeb.Plugs.RenderPublicSpec do
  @moduledoc """
  Renders the OpenAPI spec with Internal.* tagged paths removed.

  ApiSpec (full spec) is kept intact for CastAndValidate operationId lookup.
  This plug filters on the fly before rendering so SwaggerUI/ReDoc only show
  public endpoints.
  """

  @behaviour Plug

  @internal_tag_prefix "Internal."

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    spec =
      EdgeAdminWeb.ApiSpec.spec()
      |> filter_internal_paths()
      |> filter_internal_schemas()

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(spec))
  end

  defp filter_internal_paths(%OpenApiSpex.OpenApi{paths: paths} = spec) do
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

  defp filter_internal_schemas(%OpenApiSpex.OpenApi{components: nil} = spec), do: spec

  defp filter_internal_schemas(%OpenApiSpex.OpenApi{components: components} = spec) do
    filtered_schemas =
      Map.reject(components.schemas || %{}, fn {key, _} ->
        String.starts_with?(to_string(key), @internal_tag_prefix)
      end)

    %{spec | components: %{components | schemas: filtered_schemas}}
  end
end
