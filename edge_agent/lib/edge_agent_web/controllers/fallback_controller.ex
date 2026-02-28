# edge_agent/lib/edge_agent_web/controllers/fallback_controller.ex
defmodule EdgeAgentWeb.Controllers.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use EdgeAgentWeb, :controller

  alias EdgeAgentWeb.Controllers.ErrorJSON

  require Logger

  # 1. Handle validation errors from Ecto changesets (422)
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: EdgeAgentWeb.Controllers.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # 2. Handle not found errors (404)
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ErrorJSON)
    |> render(:"404")
  end

  # 3. Handle forbidden errors (403)
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: ErrorJSON)
    |> render(:"403")
  end

  # 4. Handle unauthorized errors (401)
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ErrorJSON)
    |> render(:"401")
  end

  # 5. Handle conflict errors (409) - duplicate resources, unique constraints
  def call(conn, {:error, :conflict}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: ErrorJSON)
    |> render(:"409")
  end

  # 5a. Handle conflict errors (409) with a specific reason (from checks/ modules)
  def call(conn, {:error, {:conflict, reason}}) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: reason}})
  end

  # 6. Handle service unavailable errors (503)
  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(json: ErrorJSON)
    |> render(:"503")
  end

  # 7. Handle bad request errors (400)
  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: ErrorJSON)
    |> render(:"400")
  end

  # 8. Handle business logic errors with descriptive messages (422)
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: reason}})
  end

  # 9. CATCH-ALL: Unknown errors → 500 Internal Server Error
  def call(conn, {:error, reason}) do
    Logger.error("Unhandled error in controller: #{inspect(reason)}")

    conn
    |> put_status(:internal_server_error)
    |> put_view(json: ErrorJSON)
    |> render(:"500")
  end
end
