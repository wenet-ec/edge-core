# edge_admin_web/controllers/agents/self_update_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SelfUpdateController do
  @moduledoc """
  Controller for agent self-update HTTP fallback endpoints.

  Provides endpoints for agents to check for pending self-updates when VPN
  connectivity is unavailable. This enables self-update functionality via
  HTTP fallback polling.
  """

  use EdgeAdminWeb, :controller

  alias EdgeAdmin.SelfUpdates

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:check]

  @doc """
  Checks if the latest self-update request includes the current node.

  Used by HTTP fallback mechanism for agents to poll for self-updates.

  ## Response
  - 200 OK: Returns `%{including_me: boolean, inserted_at: datetime | nil}`
  """
  def check(conn, _params) do
    node = conn.assigns.current_node

    with {:ok, result} <- SelfUpdates.check_for_latest_request(node) do
      render(conn, :check, result: result)
    end
  end
end
