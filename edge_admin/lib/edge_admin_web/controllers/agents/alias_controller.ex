# edge_admin/lib/edge_admin_web/controllers/agents/alias_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.AliasController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.Agents.AliasSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer

  tags(["Internal.Agents"])

  operation(:create,
    summary: "Register an alias for the calling agent's node",
    description:
      "Register a friendly name alias for the calling node. Returns 409 if the name is already taken in this cluster.",
    request_body: {"Alias name", "application/json", AliasSchemas.CreateAliasRequest, required: true},
    responses: %{
      201 => {"Alias created", "application/json", AliasSchemas.AliasSingleResponse},
      409 => {"Name already taken in this cluster (agent ignores)", "application/json", CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def create(conn, params) do
    node = conn.assigns.current_node

    with {:ok, alias_record} <- Nodes.create_alias(node, Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> render(:show, conn: conn, alias: alias_record)
    end
  end
end
