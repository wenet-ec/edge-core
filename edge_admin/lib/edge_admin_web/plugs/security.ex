# edge_admin/lib/edge_admin_web/plugs/security.ex
defmodule EdgeAdminWeb.Plugs.Security do
  @moduledoc false
  @behaviour Plug

  import Phoenix.Controller, only: [put_secure_browser_headers: 2]

  @doc """
  This plug adds Phoenix secure HTTP headers including a
  “Content-Security-Policy” header to responses.You will need to customize each
  policy directive to fit your application needs.
  """

  def init(opts), do: opts

  def call(conn, _) do
    # Check if this is a documentation route (SwaggerUI or ReDoc)
    if conn.request_path in ["/swaggerui", "/redoc", "/asyncdoc"] do
      # More permissive CSP for documentation UIs
      docs_directives = [
        "default-src #{default_src_directive()}",
        "form-action #{form_action_directive()}",
        "media-src #{media_src_directive()}",
        "img-src #{docs_image_src_directive()}",
        "script-src #{docs_script_src_directive()}",
        "font-src #{docs_font_src_directive()}",
        "connect-src #{docs_connect_src_directive()}",
        "style-src #{docs_style_src_directive()}",
        "frame-src #{frame_src_directive()}"
      ]

      put_secure_browser_headers(conn, %{"content-security-policy" => Enum.join(docs_directives, "; ")})
    else
      # Regular CSP for other routes
      directives = [
        "default-src #{default_src_directive()}",
        "form-action #{form_action_directive()}",
        "media-src #{media_src_directive()}",
        "img-src #{image_src_directive()}",
        "script-src #{script_src_directive()}",
        "font-src #{font_src_directive()}",
        "connect-src #{connect_src_directive()}",
        "style-src #{style_src_directive()}",
        "frame-src #{frame_src_directive()}"
      ]

      put_secure_browser_headers(conn, %{"content-security-policy" => Enum.join(directives, "; ")})
    end
  end

  # Regular CSP directives (existing)
  defp default_src_directive, do: "'none'"
  defp form_action_directive, do: "'self'"
  defp media_src_directive, do: "'self'"
  defp font_src_directive, do: "'self' data:"
  defp connect_src_directive, do: "'self'"
  defp style_src_directive, do: "'self' 'unsafe-inline'"
  defp frame_src_directive, do: "'self'"
  defp image_src_directive, do: "'self' data:"

  defp script_src_directive do
    if Application.get_env(:edge_admin, __MODULE__)[:allow_unsafe_scripts] do
      "'self' 'unsafe-eval' 'unsafe-inline'"
    else
      "'self'"
    end
  end

  # Documentation UIs CSP directives (SwaggerUI + ReDoc)
  defp docs_style_src_directive do
    "'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://fonts.googleapis.com https://unpkg.com"
  end

  defp docs_script_src_directive do
    "'self' 'unsafe-eval' 'unsafe-inline' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com"
  end

  defp docs_font_src_directive do
    "'self' https://cdnjs.cloudflare.com https://fonts.googleapis.com https://fonts.gstatic.com"
  end

  defp docs_connect_src_directive, do: "'self' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com"

  defp docs_image_src_directive do
    "'self' data: https://cdnjs.cloudflare.com https://validator.swagger.io https://cdn.jsdelivr.net"
  end
end
