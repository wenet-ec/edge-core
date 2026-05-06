# edge_agent/lib/edge_agent_web/plugs/security.ex
defmodule EdgeAgentWeb.Plugs.Security do
  @moduledoc """
  Sets secure browser headers (CSP + the defaults from
  `Phoenix.Controller.put_secure_browser_headers/2`) on every endpoint
  response. The agent serves a JSON API only — no HTML — so the policy
  is deliberately strict (`default-src 'none'`).

  ## Tuning

  Operators can opt into permissive script execution for local dev or
  embedded debug tools by setting:

      config :edge_agent, EdgeAgentWeb.Plugs.Security, allow_unsafe_scripts: true

  This widens `script-src` to include `'unsafe-eval'` and `'unsafe-inline'`.
  Production deployments should leave it off.
  """
  @behaviour Plug

  import Phoenix.Controller, only: [put_secure_browser_headers: 2]

  def init(opts), do: opts

  def call(conn, _) do
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
