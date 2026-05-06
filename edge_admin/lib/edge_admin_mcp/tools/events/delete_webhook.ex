# edge_admin/lib/edge_admin_mcp/tools/events/delete_webhook.ex
defmodule EdgeAdminMcp.Tools.Events.DeleteWebhook do
  @moduledoc """
  Delete a webhook subscription.

  Webhooks are immutable — there is no `enabled` toggle and no update API.
  To pause delivery, delete the webhook; to resume, create a new one
  with the same URL/events. Receivers verifying `X-Edge-Signature` will
  need the secret you used at create time, so plan key handoff before
  deleting if you intend to recreate.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Webhooks

  @impl true
  def title, do: "Delete Webhook"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false}

  schema do
    field :webhook_id, {:required, :string}
  end

  @impl true
  def execute(%{webhook_id: id}, frame) do
    with {:ok, webhook} <- Webhooks.get_webhook(id),
         {:ok, _} <- Webhooks.delete_webhook(webhook) do
      {:reply, Response.text(Response.tool(), "Webhook #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Webhook #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
