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
  - If SELF_UPDATE_ENABLED=true: Spawns an unsupervised Task that calls
    Watchtower asynchronously and returns 202 immediately. Failures
    inside the Task are logged but never surface as HTTP errors here —
    the agent expects to be restarted by Watchtower mid-call, so we
    can't reliably wait for a result.

  ## Response Codes
  - 202 Accepted: Update Task spawned (Watchtower may or may not succeed)
  - 403 Forbidden: Self-update feature not enabled
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
