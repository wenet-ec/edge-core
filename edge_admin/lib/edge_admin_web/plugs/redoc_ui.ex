defmodule EdgeAdminWeb.Plugs.RedocUI do
  @moduledoc """
  Renders ReDoc with the Edge Core navy + gold palette.

  Replaces the external `redoc_ui_plug` Hex package because that plug doesn't
  expose ReDoc's `theme` attribute. The brand theme is baked in.

  ## Usage

      get "/redoc", EdgeAdminWeb.Plugs.RedocUI, spec_url: "/api/openapi"

  ## Security

  The HTML response body is built **entirely from compile-time constants** —
  the spec URL pattern, the ReDoc CDN URL, and the brand theme JSON are all
  module attributes interpolated at compile time. `call/2` sends the precomputed
  `@html` constant verbatim with no per-request interpolation, mirroring the
  AsyncAPI doc controller's pattern. No XSS surface from request data.
  """

  @behaviour Plug

  @redoc_version "2.5.1"
  @redoc_cdn "https://cdn.jsdelivr.net/npm/redoc@#{@redoc_version}/bundles/redoc.standalone.js"

  # Pin the spec URL at compile time. If you ever need to expose ReDoc for a
  # second OpenAPI document, add another module that uses a different @spec_url.
  @spec_url "/api/openapi"

  # Navy-led theme. Primary, links, headings, sidebar accents → navy.
  # HTTP method colors are intentionally NOT overridden — ReDoc's defaults
  # (green POST, blue GET, etc.) are what developers expect to see.
  @theme_json JSON.encode!(%{
                colors: %{
                  primary: %{main: "#3e567c"},
                  text: %{primary: "#24344d", secondary: "#506d96"},
                  border: %{dark: "#e1e5eb", light: "#ffffff"}
                },
                typography: %{
                  fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif",
                  headings: %{fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"},
                  links: %{color: "#3e567c", hover: "#2e4263"}
                },
                sidebar: %{
                  backgroundColor: "#fafbfc",
                  textColor: "#24344d",
                  activeTextColor: "#3e567c"
                },
                rightPanel: %{
                  backgroundColor: "#24344d",
                  textColor: "#ffffff"
                }
              })

  # Built entirely from compile-time constants — no runtime interpolation.
  @html """
  <!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Edge Admin — REST API Reference</title>
      <link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin />
      <style>
        html, body { margin: 0; padding: 0; }
        body { font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
      </style>
    </head>
    <body>
      <redoc spec-url="#{@spec_url}" theme='#{@theme_json}'></redoc>
      <script src="#{@redoc_cdn}"></script>
    </body>
  </html>
  """

  @impl Plug
  def init(opts) do
    case Keyword.get(opts, :spec_url) do
      nil ->
        :ok

      url when url == @spec_url ->
        :ok

      other ->
        raise ArgumentError,
              "EdgeAdminWeb.Plugs.RedocUI is hardcoded to spec_url=#{@spec_url}; got #{inspect(other)}"
    end

    :ok
  end

  @impl Plug
  def call(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, @html)
  end
end
