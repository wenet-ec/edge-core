# edge_agent/lib/edge_agent_web/plugs/security.ex
defmodule EdgeAgentWeb.Plugs.Security do
  @moduledoc false
  @behaviour Plug

  import Phoenix.Controller, only: [put_secure_browser_headers: 2]

  def init(opts), do: opts

  def call(conn, _) do
    # Remove the SwaggerUI check and just use regular CSP
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

  # Keep only the regular CSP directives, remove all swagger_* functions
  defp default_src_directive, do: "'none'"
  defp form_action_directive, do: "'self'"
  defp media_src_directive, do: "'self'"
  defp font_src_directive, do: "'self'"
  defp connect_src_directive, do: "'self'"
  defp style_src_directive, do: "'self' 'unsafe-inline'"
  defp frame_src_directive, do: "'self'"
  defp image_src_directive, do: "'self' data:"

  defp script_src_directive do
    if Application.get_env(:edge_agent, __MODULE__)[:allow_unsafe_scripts] do
      "'self' 'unsafe-eval' 'unsafe-inline'"
    else
      "'self'"
    end
  end
end
