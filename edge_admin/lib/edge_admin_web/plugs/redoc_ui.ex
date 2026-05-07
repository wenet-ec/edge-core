defmodule EdgeAdminWeb.Plugs.RedocUI do
  @moduledoc """
  Renders ReDoc with the Edge Core navy + gold palette.

  Replaces the external `redoc_ui_plug` Hex package because that plug doesn't
  expose ReDoc's `theme` attribute. Same surface (one option, `spec_url`),
  with the brand theme baked in.

  ## Usage

      get "/redoc", EdgeAdminWeb.Plugs.RedocUI, spec_url: "/api/openapi"
  """

  @behaviour Plug

  @redoc_version "2.5.0"
  @redoc_cdn "https://cdn.jsdelivr.net/npm/redoc@#{@redoc_version}/bundles/redoc.standalone.js"

  # Navy-led theme. Primary, links, headings, sidebar accents → navy.
  # HTTP method colors are intentionally NOT overridden — ReDoc's defaults
  # (green POST, blue GET, etc.) are what developers expect to see.
  # Gold appears sparingly on the right-panel code block accent only.
  @theme %{
    colors: %{
      primary: %{main: "#3e567c"},
      text: %{primary: "#24344d", secondary: "#506d96"},
      border: %{dark: "#e1e5eb", light: "#ffffff"}
    },
    typography: %{
      fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif",
      headings: %{fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif"},
      links: %{
        color: "#3e567c",
        hover: "#2e4263"
      }
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
  }

  @impl Plug
  def init(opts) do
    spec_url =
      Keyword.get(opts, :spec_url) ||
        raise ArgumentError, "EdgeAdminWeb.Plugs.RedocUI requires :spec_url option"

    %{spec_url: spec_url, theme_json: Jason.encode!(@theme)}
  end

  @impl Plug
  def call(conn, %{spec_url: spec_url, theme_json: theme_json}) do
    html = render(spec_url, theme_json)

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, html)
  end

  defp render(spec_url, theme_json) do
    # The `theme` attribute on <redoc> is parsed as JSON — see redoc/src/standalone.tsx.
    # Use a single-quoted attribute so the embedded JSON's double quotes don't need escaping.
    """
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
        <redoc spec-url="#{Plug.HTML.html_escape(spec_url)}" theme='#{theme_json}'></redoc>
        <script src="#{@redoc_cdn}"></script>
      </body>
    </html>
    """
  end
end
