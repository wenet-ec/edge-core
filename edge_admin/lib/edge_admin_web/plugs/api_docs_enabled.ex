# edge_admin/lib/edge_admin_web/plugs/api_docs_enabled.ex
defmodule EdgeAdminWeb.Plugs.ApiDocsEnabled do
  @moduledoc """
  Plug to conditionally allow access to API documentation endpoints.

  Gates the following routes — returns 404 when disabled:
  - `/swaggerui` — Swagger UI
  - `/redoc` — ReDoc
  - `/asyncdoc` — AsyncAPI viewer
  - `/api/openapi` — OpenAPI JSON spec
  - `/api/asyncapi` — AsyncAPI JSON spec

  This plug checks the API_DOCS_ENABLED configuration and returns 404 if disabled.
  Useful for production environments where you want to disable API documentation exposure.

  ## Configuration

  Set in config/runtime.exs:

      config :edge_admin, api_docs_enabled: true

  Or via environment variable:

      API_DOCS_ENABLED=false
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
      |> send_resp(:not_found, Jason.encode!(%{errors: %{detail: "Not Found"}}))
      |> halt()
    end
  end

  defp api_docs_enabled? do
    Application.get_env(:edge_admin, :api_docs_enabled, true)
  end
end
