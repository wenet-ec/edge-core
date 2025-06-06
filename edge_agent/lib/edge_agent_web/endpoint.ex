# edge_agent/lib/edge_agent_web/endpoint.ex
defmodule EdgeAgentWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :edge_agent

  alias Plug.Conn

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: {EdgeAgentWeb.Session, :config, []}]],
    longpoll: [connect_info: [session: {EdgeAgentWeb.Session, :config, []}]]
  )

  plug(EdgeAgentWeb.Plugs.Security)
  plug(:ping)
  plug(:cors)
  plug(:basic_auth)

  # Serve static files
  plug(Plug.Static,
    at: "/",
    from: :edge_agent,
    gzip: true,
    only: EdgeAgentWeb.static_paths()
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :edge_agent)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # Use the session function instead of calling the module directly
  plug(:session)

  plug(EdgeAgentHealth.Router)
  plug(:halt_if_sent)
  plug(EdgeAgentWeb.Router)

  # Add the session function
  defp session(conn, _opts) do
    opts = Plug.Session.init(EdgeAgentWeb.Session.config())
    Plug.Session.call(conn, opts)
  end

  # Your existing plug functions...
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

  defp cors(conn, _opts) do
    opts = Corsica.init(Application.get_env(:edge_agent, Corsica))

    Corsica.call(conn, opts)
  end

  defp basic_auth(conn, _opts) do
    basic_auth_config = Application.get_env(:edge_agent, :basic_auth)

    if basic_auth_config[:username] do
      Plug.BasicAuth.basic_auth(conn, basic_auth_config)
    else
      conn
    end
  end

  # Splitting routers in separate modules has a negative side effect:
  # Phoenix.Router does not check the Plug.Conn state and tries to match the
  # route even if it was already handled/sent by another router.
  defp halt_if_sent(%{state: :sent, halted: false} = conn, _opts), do: halt(conn)
  defp halt_if_sent(conn, _opts), do: conn
end
