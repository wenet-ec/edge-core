# edge_agent/lib/edge_agent_web/session.ex
defmodule EdgeAgentWeb.Session do
  @moduledoc false
  def config do
    [
      store: :cookie,
      key: app_config(:session_key),
      signing_salt: app_config(:session_signing_salt),
      same_site: "Lax"
    ]
  end

  defp app_config(key) do
    Keyword.fetch!(Application.get_env(:edge_agent, EdgeAgentWeb.Endpoint), key)
  end
end
