# edge_admin/lib/edge_admin_web/controllers/events/webhook_controller.ex
defmodule EdgeAdminWeb.Controllers.Events.WebhookController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Events.WebhookSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Events.Webhook"])

  operation(:index,
    summary: "List webhooks",
    description:
      "Returns a paginated list of webhook subscriptions. The full catalog of event types you can subscribe to is documented in the [AsyncAPI spec](/asyncdoc).",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,url", order_directions_example: "desc,asc") ++
        [
          QueryParams.string_filter(:url,
            description: "Filter by URL (exact match or wildcard: prefix*, *suffix, *substring*)"
          ),
          QueryParams.string_filter(:event_type,
            description:
              "Returns webhooks whose `subscribed_events` list contains this event type. Pass a literal event type, e.g. `edge.node.registered`. See [AsyncAPI spec](/asyncdoc) for the catalog."
          )
        ] ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 => {"Paginated webhooks", "application/json", WebhookSchemas.WebhookPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {webhooks, meta}} <- Webhooks.list_webhooks(params) do
      render(conn, :index, conn: conn, webhooks: webhooks, meta: meta)
    end
  end

  operation(:show,
    summary: "Get webhook",
    description: "Get a single webhook by ID.",
    parameters: [PathParams.uuid(:id, "Webhook ID")],
    responses: %{
      200 => {"Webhook", "application/json", WebhookSchemas.WebhookSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Webhook not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, webhook} <- Webhooks.get_webhook(id) do
      render(conn, :show, conn: conn, webhook: webhook)
    end
  end

  operation(:create,
    summary: "Create webhook",
    description:
      "Create a webhook subscription. The destination URL is validated against the SSRF deny list at create time. `secret` (HMAC signing key, >= 32 bytes) and `headers` are write-only — encrypted at rest and never returned in any GET response. `subscribed_events` is an explicit list of event types this webhook fires on; the full catalog is documented in the [AsyncAPI spec](/asyncdoc).",
    request_body: {"Webhook creation data", "application/json", WebhookSchemas.WebhookCreateRequest, required: true},
    responses: %{
      201 => {"Webhook created", "application/json", WebhookSchemas.WebhookSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, _params) do
    with {:ok, %Webhook{} = webhook} <- Webhooks.create_webhook(conn.body_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/webhooks/#{webhook}")
      |> render(:show, conn: conn, webhook: webhook)
    end
  end

  operation(:delete,
    summary: "Delete webhook",
    description:
      "Permanently delete a webhook. Webhooks are immutable after create — to change any field (URL, secret, headers, subscribed_events) delete and recreate. The retry budget is process-wide (`WEBHOOK_MAX_ATTEMPTS` env var on the admin), not per-webhook.",
    parameters: [PathParams.uuid(:id, "Webhook ID")],
    responses: %{
      204 => {"Webhook deleted", "", nil},
      404 => {"Webhook not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, webhook} <- Webhooks.get_webhook(id),
         {:ok, %Webhook{}} <- Webhooks.delete_webhook(webhook) do
      send_resp(conn, :no_content, "")
    end
  end
end
