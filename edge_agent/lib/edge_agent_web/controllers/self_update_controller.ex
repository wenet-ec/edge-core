# edge_agent/lib/edge_agent_web/controllers/self_update_controller.ex
defmodule EdgeAgentWeb.Controllers.SelfUpdateController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.SelfUpdates
  alias EdgeAgentWeb.ResponseEnvelope

  action_fallback(EdgeAgentWeb.Controllers.FallbackController)

  @doc """
  Requests an asynchronous self-update.

  Returns 403 when self-updates are disabled and 202 after the request is
  accepted. Watchtower failures are logged by the background task rather than
  returned to this HTTP request.
  """
  def trigger(conn, _params) do
    with :ok <- SelfUpdates.check_enabled() do
      SelfUpdates.trigger_update_async()

      conn
      |> put_status(:accepted)
      |> json(ResponseEnvelope.success(conn, %{message: "Self-update triggered successfully"}))
    end
  end
end
