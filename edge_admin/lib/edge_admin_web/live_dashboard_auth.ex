# edge_admin/lib/edge_admin_web/live_dashboard_auth.ex
defmodule EdgeAdminWeb.LiveDashboardAuth do
  @moduledoc """
  LiveView hook that gates LiveDashboard access at runtime.

  When `LIVE_DASHBOARD_ENABLED=false`, halts the mount and redirects to `/`
  with a flash error. The redirect (rather than a 404) keeps the dashboard
  routes visible in the router but unreachable as a UI when disabled.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if Application.get_env(:edge_admin, :live_dashboard_enabled, false) do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "LiveDashboard is not enabled")
        |> redirect(to: "/")

      {:halt, socket}
    end
  end
end
