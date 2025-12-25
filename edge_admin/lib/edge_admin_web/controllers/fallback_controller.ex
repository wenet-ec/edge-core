# edge_admin/lib/edge_admin_web/controllers/fallback_controller.ex
defmodule EdgeAdminWeb.Controllers.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use EdgeAdminWeb, :controller

  # Handle validation errors from Ecto changesets
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: EdgeAdminWeb.Controllers.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # Handle generic not found errors
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: EdgeAdminWeb.Controllers.ErrorJSON)
    |> render(:"404")
  end

  # Handle forbidden errors (e.g., agent trying to update execution that doesn't belong to them)
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Forbidden"})
  end

  # Handle service unavailable errors (metrics, gateway issues, etc.)
  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Service unavailable"})
  end

  # Handle business logic errors with descriptive messages
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end

  # Fallback for unexpected error formats
  def call(conn, {:error, reason}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: inspect(reason)})
  end
end
