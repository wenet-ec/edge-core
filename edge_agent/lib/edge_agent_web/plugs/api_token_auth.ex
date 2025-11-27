# edge_agent_web/lib/edge_agent_web/plugs/api_token_auth.ex
defmodule EdgeAgentWeb.Plugs.ApiTokenAuth do
  @moduledoc """
  Plug for authenticating API requests using bearer token.

  Retrieves the API token from Settings table and validates against
  the Authorization header. Returns 401 if token is missing or invalid.
  """

  import Plug.Conn

  alias EdgeAgent.Settings

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- get_token_from_header(conn),
         {:ok, stored_token} <- get_stored_token(),
         true <- token == stored_token do
      conn
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
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
    case Settings.get("api_token") do
      nil ->
        {:error, :no_token_configured}

      token ->
        {:ok, token}
    end
  end
end
