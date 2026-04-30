# edge_agent/lib/edge_agent_web/endpoint.ex
defmodule EdgeAgentWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :edge_agent

  alias Plug.Conn

  plug(EdgeAgentWeb.Plugs.Security)
  plug(:ping)

  # Code reloading (dev only)
  if code_reloading? do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :edge_agent)
  end

  # AssignRequestId both generates a UUIDv7 and sets the response header, so
  # `Plug.RequestId` is redundant. Agent is a request origin, not a relay —
  # we don't honor inbound x-request-id from upstream.
  plug(EdgeAgentWeb.Plugs.AssignRequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(
    Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  plug(EdgeAgentHealth.Router)
  plug(:halt_if_sent)

  # PromEx metrics with api_token authentication
  plug(:metrics_auth_conditional)
  plug(PromEx.Plug, prom_ex_module: EdgeAgent.PromEx, path: "/api/v1/agents/me/metrics/raw")

  plug(EdgeAgentWeb.Router)

  # sobelow_skip ["XSS.SendResp"]
  defp ping(%{request_path: "/ping"} = conn, _opts) do
    version = Application.get_env(:edge_agent, :version)
    response = Jason.encode!(%{status: "ok", version: version})

    conn
    |> Conn.put_resp_header("content-type", "application/json")
    |> Conn.send_resp(200, response)
    |> Conn.halt()
  end

  defp ping(conn, _opts), do: conn

  # Apply api_token auth only for the metrics endpoint (if enabled)
  defp metrics_auth_conditional(%{request_path: "/api/v1/agents/me/metrics/raw"} = conn, _opts) do
    auth_enabled = Application.get_env(:edge_agent, :agent_metrics_auth_enabled, true)

    if auth_enabled do
      EdgeAgentWeb.Plugs.ApiTokenAuth.call(conn, [])
    else
      conn
    end
  end

  defp metrics_auth_conditional(conn, _opts), do: conn

  # Splitting routers in separate modules has a negative side effect:
  # Phoenix.Router does not check the Plug.Conn state and tries to match the
  # route even if it was already handled/sent by another router.
  defp halt_if_sent(%{state: :sent, halted: false} = conn, _opts), do: halt(conn)
  defp halt_if_sent(conn, _opts), do: conn
end
