# edge_admin/lib/edge_admin_web/admin_debug_auth.ex
defmodule EdgeAdminWeb.AdminDebugAuth do
  @moduledoc """
  LiveView hook that gates Admin debug access at runtime.

  When `ADMIN_DEBUG_ENABLED=false`, halts the mount and redirects to `/`
  with a flash error. The redirect (rather than a 404) keeps the dashboard
  routes visible in the router but unreachable as a UI when disabled.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if Application.get_env(:edge_admin, :admin_debug_enabled, false) do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "Admin debug is not enabled")
        |> redirect(to: "/")

      {:halt, socket}
    end
  end
end
