# edge_admin/lib/edge_admin_web/controllers/fallback_controller.ex
defmodule EdgeAdminWeb.Controllers.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use EdgeAdminWeb, :controller

  alias EdgeAdminWeb.Controllers.ChangesetJSON
  alias EdgeAdminWeb.Controllers.ErrorJSON
  alias EdgeAdminWeb.ResponseEnvelope

  require Logger

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ChangesetJSON)
    |> render(:error, conn: conn, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ErrorJSON)
    |> render(:"404", conn: conn)
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: ErrorJSON)
    |> render(:"403", conn: conn)
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ErrorJSON)
    |> render(:"401", conn: conn)
  end

  # Prefer `{:error, {:conflict, reason}}` for user-facing endpoints.
  def call(conn, {:error, :conflict}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: ErrorJSON)
    |> render(:"409", conn: conn)
  end

  def call(conn, {:error, {:conflict, reason}}) do
    conn
    |> put_status(:conflict)
    |> json(ResponseEnvelope.error(conn, "conflict", reason))
  end

  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(json: ErrorJSON)
    |> render(:"503", conn: conn)
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: ErrorJSON)
    |> render(:"400", conn: conn)
  end

  # Unhandled error paths indicate a bug or missing fallback clause.
  def call(conn, {:error, reason}) do
    Logger.error("Unhandled error in controller: #{inspect(reason)}")

    conn
    |> put_status(:internal_server_error)
    |> put_view(json: ErrorJSON)
    |> render(:"500", conn: conn)
  end
end
