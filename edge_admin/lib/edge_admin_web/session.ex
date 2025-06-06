# edge_admin/lib/edge_admin_web/session.ex
defmodule EdgeAdminWeb.Session do
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
    Keyword.fetch!(Application.get_env(:edge_admin, EdgeAdminWeb.Endpoint), key)
  end
end
