# edge_admin/lib/edge_admin_web/controllers/self_updates/self_update_request_controller.ex
defmodule EdgeAdminWeb.Controllers.SelfUpdates.SelfUpdateRequestController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.SelfUpdates.SelfUpdateRequestSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:create]
  plug DegradedMode, :allow when action in [:index, :show, :delete]

  tags(["SelfUpdates.Request"])

  operation(:index,
    summary: "List all self-update requests",
    description: "Returns a paginated list of all self-update requests with filtering and sorting",
    parameters: [
      page: [
        in: :query,
        description: "Page number",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, default: 1},
        example: 1
      ],
      page_size: [
        in: :query,
        description: "Items per page",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 100, default: 20},
        example: 20
      ],
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at"
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc)",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc"
      ],
      status: [
        in: :query,
        description: "Filter by status",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["pending", "processing", "completed"]}
      ],
      inserted_at__gte: [
        in: :query,
        description: "Filter requests inserted after or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ],
      inserted_at__lte: [
        in: :query,
        description: "Filter requests inserted before or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated list of self-update requests", "application/json",
         SelfUpdateRequestSchemas.SelfUpdateRequestPaginatedResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {requests, meta}} <- SelfUpdates.list_self_update_requests(params) do
      render(conn, :index, requests: requests, meta: meta)
    end
  end

  operation(:create,
    summary: "Create a new self-update request",
    description: """
    Create a new self-update request to trigger agent updates.

    The request will be processed asynchronously. Only healthy nodes with self_update_enabled=true will be updated.

    Targeting types:
    - 'all': Target all nodes (with optional filters)
    - 'nodes': Target specific nodes by IDs (with optional filters)
    - 'clusters': Target specific clusters by names (with optional filters)

    Node and cluster filters can be applied to further refine targeting.
    """,
    request_body:
      {"Self-update request creation parameters", "application/json",
       SelfUpdateRequestSchemas.SelfUpdateRequestCreateRequest},
    responses: %{
      201 =>
        {"Self-update request created successfully", "application/json",
         SelfUpdateRequestSchemas.SelfUpdateRequestSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, params) do
    with {:ok, %SelfUpdateRequest{} = request} <- SelfUpdates.create_self_update_request(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/self_update_requests/#{request.id}")
      |> render(:show, request: request)
    end
  end

  operation(:show,
    summary: "Get a specific self-update request",
    description: "Returns details for a specific self-update request by ID",
    parameters: [
      id: [
        in: :path,
        description: "Self-update request ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Self-update request details", "application/json", SelfUpdateRequestSchemas.SelfUpdateRequestSingleResponse},
      404 => {"Self-update request not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    with {:ok, request} <- SelfUpdates.get_self_update_request(id) do
      render(conn, :show, request: request)
    end
  end

  operation(:delete,
    summary: "Delete a self-update request",
    description: """
    Delete a self-update request.

    Only completed requests can be deleted.
    Attempting to delete a pending or processing request will return 409.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Self-update request ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"Self-update request deleted successfully", "", nil},
      404 => {"Self-update request not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Cannot delete non-completed request", "application/json", CommonSchemas.ConflictResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    with {:ok, request} <- SelfUpdates.get_self_update_request(id),
         {:ok, _request} <- SelfUpdates.delete_self_update_request(request) do
      send_resp(conn, :no_content, "")
    end
  end
end
