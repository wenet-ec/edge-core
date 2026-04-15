# edge_admin/lib/edge_admin_web/plugs/cast_and_validate_error_renderer.ex
defmodule EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer do
  @moduledoc """
  Custom render_error plug for `OpenApiSpex.Plug.CastAndValidate`.

  Formats schema validation errors (invalid path/query params or request body)
  into the standard API envelope so clients always see the same shape:

      {
        "error": {
          "code": "bad_request",
          "message": "Invalid request parameters",
          "details": {
            "name": ["Invalid format. Expected ~r/…/"],
            "ipv4_range": ["Invalid format. Expected ~r/…/"]
          }
        },
        "meta": { "request_id": "…", "timestamp": "…" }
      }

  Wire it up in every controller instead of `json_render_error_v2: true`:

      plug OpenApiSpex.Plug.CastAndValidate,
        render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  """

  @behaviour Plug

  alias EdgeAdminWeb.ResponseEnvelope
  alias OpenApiSpex.OpenApi
  alias Plug.Conn

  @impl Plug
  def init(errors), do: errors

  @impl Plug
  def call(conn, errors) when is_list(errors) do
    details =
      Enum.group_by(
        errors,
        fn error -> error |> OpenApiSpex.path_to_string() |> strip_leading_slash() end,
        &to_string/1
      )

    body =
      ResponseEnvelope.error(conn, "bad_request", "Invalid request parameters", details)

    json = OpenApi.json_encoder().encode!(body)

    conn
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(400, json)
  end

  def call(conn, reason), do: call(conn, [reason])

  defp strip_leading_slash("/" <> rest), do: rest
  defp strip_leading_slash(key), do: key
end
