# edge_admin/lib/edge_admin_mcp/http_server.ex
defmodule EdgeAdminMcp.HttpServer do
  @moduledoc """
  Dedicated Bandit listener for the Admin MCP Streamable HTTP endpoint.

  MCP is exposed at `/mcp` on `ADMIN_MCP_PORT`. Authentication and tool access
  are handled by `EdgeAdminMcp.Server` from the MCP request context.
  """

  @behaviour Plug

  import Plug.Conn

  alias Plug.Conn

  @mcp_path "/mcp"

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  def start_link(_opts) do
    if Application.get_env(:edge_admin, :admin_mcp_dedicated, false) do
      Bandit.start_link(
        plug: __MODULE__,
        scheme: :http,
        port: Application.fetch_env!(:edge_admin, :admin_mcp_port),
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      )
    else
      :ignore
    end
  end

  @impl true
  def init(opts) do
    opts
    |> Keyword.put(:server, EdgeAdminMcp.Server)
    |> Anubis.Server.Transport.StreamableHTTP.Plug.init()
  end

  @impl true
  def call(%Conn{request_path: @mcp_path} = conn, opts) do
    Anubis.Server.Transport.StreamableHTTP.Plug.call(conn, opts)
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
    |> halt()
  end
end
