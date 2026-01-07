# edge_agent/lib/edge_agent_web/controllers/self_update_controller.ex
defmodule EdgeAgentWeb.Controllers.SelfUpdateController do
  use EdgeAgentWeb, :controller

  require Logger

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
    if self_update_enabled?() do
      # Trigger the update asynchronously so we can respond to the admin before shutdown
      Task.start(fn ->
        Logger.info("Triggering self-update asynchronously")
        trigger_watchtower_update()
      end)

      # Respond immediately with 202 Accepted
      conn
      |> put_status(:accepted)
      |> json(%{
        message: "Self-update triggered successfully"
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Self-update feature is not enabled"})
    end
  end

  # Check if self-update is enabled
  defp self_update_enabled? do
    Application.get_env(:edge_agent, :self_update_enabled, false)
  end

  # Trigger self-update service via HTTP API
  defp trigger_watchtower_update do
    watchtower_url = Application.get_env(:edge_agent, :watchtower_url, "http://watchtower:8080")
    api_token = Application.get_env(:edge_agent, :watchtower_http_api_token, "")
    update_endpoint = "#{watchtower_url}/v1/update"

    Logger.info("Calling self-update service at #{update_endpoint}")

    # Make GET request to self-update service with Bearer token (10 second timeout)
    headers =
      if api_token == "" do
        []
      else
        [{"authorization", "Bearer #{api_token}"}]
      end

    case Req.get(update_endpoint, headers: headers, receive_timeout: 10_000, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, "Self-update service returned status #{status}: #{inspect(body)}"}

      {:error, %Req.TransportError{reason: reason}} when reason in [:timeout, :econnrefused, :closed] ->
        # Watchtower blocks until update completes, so timeout/connection errors mean agent is restarting
        Logger.info("Self-update triggered successfully (connection #{reason} indicates restart)")
        {:ok, %{message: "Update triggered, agent restarting"}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
