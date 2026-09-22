# edge_admin/lib/edge_admin_web/plugs/api_docs_enabled.ex
defmodule EdgeAdminWeb.Plugs.ApiDocsEnabled do
  @moduledoc """
  Plug to conditionally allow access to API documentation endpoints.

  Returns 404 for the documentation surface when `API_DOCS_ENABLED=false`.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if api_docs_enabled?() do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_resp_content_type("application/json")
      |> send_resp(:not_found, JSON.encode!(%{errors: %{detail: "Not Found"}}))
      |> halt()
    end
  end

  defp api_docs_enabled? do
    Application.get_env(:edge_admin, :api_docs_enabled, true)
  end
end
