# edge_agent/lib/edge_agent_web/controllers/fallback_controller.ex
defmodule EdgeAgentWeb.Controllers.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use EdgeAgentWeb, :controller

  alias EdgeAgentWeb.Controllers.ChangesetJSON
  alias EdgeAgentWeb.Controllers.ErrorJSON
  alias EdgeAgentWeb.ResponseEnvelope

  require Logger

  # 1. Changeset validation errors (422)
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ChangesetJSON)
    |> render(:error, conn: conn, changeset: changeset)
  end

  # 2. Not found (404)
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ErrorJSON)
    |> render(:"404", conn: conn)
  end

  # 3. Forbidden (403)
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: ErrorJSON)
    |> render(:"403", conn: conn)
  end

  # 4. Unauthorized (401)
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ErrorJSON)
    |> render(:"401", conn: conn)
  end

  # 5. Conflict (409) - bare atom
  def call(conn, {:error, :conflict}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: ErrorJSON)
    |> render(:"409", conn: conn)
  end

  # 6. Conflict with reason (409)
  def call(conn, {:error, {:conflict, reason}}) do
    conn
    |> put_status(:conflict)
    |> json(ResponseEnvelope.error(conn, "conflict", reason))
  end

  # 7. Service unavailable (503)
  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(json: ErrorJSON)
    |> render(:"503", conn: conn)
  end

  # 8. Bad request (400)
  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: ErrorJSON)
    |> render(:"400", conn: conn)
  end

  # 9. CATCH-ALL: unhandled error → 500
  def call(conn, {:error, reason}) do
    Logger.error("Unhandled error in controller: #{inspect(reason)}")

    conn
    |> put_status(:internal_server_error)
    |> put_view(json: ErrorJSON)
    |> render(:"500", conn: conn)
  end
end
