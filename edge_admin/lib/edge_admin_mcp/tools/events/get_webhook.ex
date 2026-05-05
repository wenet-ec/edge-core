# edge_admin/lib/edge_admin_mcp/tools/events/get_webhook.ex
defmodule EdgeAdminMcp.Tools.Events.GetWebhook do
  @moduledoc "Get a webhook subscription by ID. Secret and headers are never returned."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdminMcp.Tools.Events.WebhookData

  @impl true
  def title, do: "Get Webhook"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :webhook_id, {:required, :string}
  end

  @impl true
  def execute(%{webhook_id: id}, frame) do
    case Webhooks.get_webhook(id) do
      {:ok, webhook} ->
        {:reply, Response.json(Response.tool(), WebhookData.data(webhook)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Webhook #{id} not found"), frame}
    end
  end
end
