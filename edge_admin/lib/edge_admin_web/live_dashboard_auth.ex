# edge_admin/lib/edge_admin_web/live_dashboard_auth.ex
defmodule EdgeAdminWeb.LiveDashboardAuth do
  @moduledoc """
  LiveView hook to check if LiveDashboard is enabled at runtime.
  Returns 404 if LIVE_DASHBOARD_ENABLED=false.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if Application.get_env(:edge_admin, :live_dashboard_enabled, false) do
      {:cont, socket}
    else
      # Redirect to 404 if dashboard is disabled
      socket =
        socket
        |> put_flash(:error, "LiveDashboard is not enabled")
        |> redirect(to: "/")

      {:halt, socket}
    end
  end
end
