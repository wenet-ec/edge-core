# edge_admin/lib/edge_admin_web/admin_debug_dashboard.ex
defmodule EdgeAdminWeb.AdminDebugDashboard do
  @moduledoc """
  LiveView hook that gates Admin Debug Dashboard access at runtime.

  When `ADMIN_DEBUG_DASHBOARD_ENABLED=false`, halts the mount and redirects to
  `/`. The redirect (rather than a 404) keeps the dashboard routes visible in
  the router but unreachable as a UI when disabled.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if Application.get_env(:edge_admin, :admin_debug_dashboard_enabled, false) do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "Admin Debug Dashboard is not enabled")
        |> redirect(to: "/")

      {:halt, socket}
    end
  end
end
