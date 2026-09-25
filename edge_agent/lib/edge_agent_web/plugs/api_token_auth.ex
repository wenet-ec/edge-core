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
    with {:ok, token} <- bearer_token(get_req_header(conn, "authorization")),
         stored_token when is_binary(stored_token) <- Settings.get_api_token(),
         true <- authorized?(token, stored_token) do
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

  @doc false
  @spec bearer_token([String.t()]) :: {:ok, String.t()} | {:error, :missing_token}
  def bearer_token(["Bearer " <> token]), do: {:ok, token}
  def bearer_token(_authorization_headers), do: {:error, :missing_token}

  @doc false
  @spec authorized?(term(), term()) :: boolean()
  def authorized?(token, stored_token) when is_binary(token) and is_binary(stored_token),
    do: Plug.Crypto.secure_compare(token, stored_token)

  def authorized?(_token, _stored_token), do: false
end
