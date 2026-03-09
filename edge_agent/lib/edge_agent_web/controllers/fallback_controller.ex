# edge_agent/lib/edge_agent_web/controllers/fallback_controller.ex
defmodule EdgeAgentWeb.Controllers.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use EdgeAgentWeb, :controller

  alias EdgeAgentWeb.Controllers.ErrorJSON

  require Logger

  # 1. Changeset validation errors (422) - field-level errors from forms
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: EdgeAgentWeb.Controllers.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # 2. Not found (404)
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: ErrorJSON)
    |> render(:"404")
  end

  # 3. Forbidden (403)
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: ErrorJSON)
    |> render(:"403")
  end

  # 4. Unauthorized (401) - rare, usually handled upstream in plugs
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: ErrorJSON)
    |> render(:"401")
  end

  # 5. Conflict (409) - state-dependent: duplicate resource, unique constraint,
  #    or operation blocked by current state (may succeed after state changes)
  def call(conn, {:error, :conflict}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: ErrorJSON)
    |> render(:"409")
  end

  # 6. Conflict with reason (409) - from checks/ modules returning {:conflict, reason}
  def call(conn, {:error, {:conflict, reason}}) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: reason}})
  end

  # 7. Unprocessable with reason (422) - from checks/ modules returning {:unprocessable, reason}
  #    Semantically invalid: the request is logically contradictory regardless of when it is sent.
  #    Unlike changeset errors (field-level), these are operation-level rejections.
  def call(conn, {:error, {:unprocessable, reason}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: reason}})
  end

  # 8. Service unavailable (503) - downstream dependency unreachable (VPN, metrics, etc.)
  def call(conn, {:error, :service_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(json: ErrorJSON)
    |> render(:"503")
  end

  # 9. Bad request (400) - malformed input
  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: ErrorJSON)
    |> render(:"400")
  end

  # 10. CATCH-ALL: unhandled error → 500
  #     Indicates a bug or missing error-handling path. Always investigate these.
  def call(conn, {:error, reason}) do
    Logger.error("Unhandled error in controller: #{inspect(reason)}")

    conn
    |> put_status(:internal_server_error)
    |> put_view(json: ErrorJSON)
    |> render(:"500")
  end
end
