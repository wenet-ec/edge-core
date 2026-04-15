# edge_agent/lib/edge_agent_web/controllers/self_update_controller.ex
defmodule EdgeAgentWeb.Controllers.SelfUpdateController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.SelfUpdates
  alias EdgeAgentWeb.ResponseEnvelope

  action_fallback(EdgeAgentWeb.Controllers.FallbackController)

  @doc """
  Triggers a self-update by requesting the self-update service to update this agent container.

  ## Behavior
  - If SELF_UPDATE_ENABLED=false: Returns 403 Forbidden
  - If SELF_UPDATE_ENABLED=true: Calls self-update service API to trigger update

  ## Response Codes
  - 202 Accepted: Update request sent to self-update service successfully
  - 403 Forbidden: Self-update feature not enabled
  - 503 Service Unavailable: Self-update service unreachable or error
  """
  def trigger(conn, _params) do
    with :ok <- SelfUpdates.check_enabled() do
      # Trigger the update asynchronously so we can respond to the admin before shutdown
      SelfUpdates.trigger_update_async()

      conn
      |> put_status(:accepted)
      |> json(ResponseEnvelope.success(conn, %{message: "Self-update triggered successfully"}))
    end
  end
end
