# edge_agent/lib/edge_agent_web/plugs/api_token_auth.ex
defmodule EdgeAgentWeb.Plugs.ApiTokenAuth do
  @moduledoc """
  Plug for authenticating API requests using bearer token.

  Retrieves the API token from Settings table (set on the agent during
  bootstrap registration) and validates against the `Authorization: Bearer`
  header via `Plug.Crypto.secure_compare/2`. Returns 401 with the standard
  `ResponseEnvelope.error/3` shape if the token is missing or invalid —
  same envelope used by `FallbackController` so clients see one error
  contract across the API.
  """

  import Plug.Conn

  alias EdgeAgent.Settings
  alias EdgeAgentWeb.ResponseEnvelope

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- get_token_from_header(conn),
         {:ok, stored_token} <- get_stored_token(),
         true <- Plug.Crypto.secure_compare(token, stored_token) do
      conn
    else
      _ ->
        body = ResponseEnvelope.error(conn, "unauthorized", "Missing or invalid credentials")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, JSON.encode!(body))
        |> halt()
    end
  end

  defp get_token_from_header(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp get_stored_token do
    case Settings.get_api_token() do
      nil ->
        {:error, :no_token_configured}

      token ->
        {:ok, token}
    end
  end
end
