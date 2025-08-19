# edge_agent/lib/edge_agent_web/controllers/fallback_controller.ex
defmodule EdgeAgentWeb.Controllers.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use EdgeAgentWeb, :controller

  # Handle validation errors (changesets)
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: EdgeAgentWeb.Controllers.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # Handle not found errors
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(html: EdgeAgentWeb.ErrorHTML, json: EdgeAgentWeb.Controllers.ErrorJSON)
    |> render(:"404")
  end
end
