# edge_agent/lib/edge_agent/prom_ex/server.ex
defmodule EdgeAgent.PromEx.Server do
  @moduledoc """
  Bandit endpoint for Agent PromEx metrics.

  The normal metrics route remains mounted on the Agent API endpoint unless
  `AGENT_METRICS_PORT` is configured. In dedicated mode this Plug serves the
  same path and Agent API-token authentication from a dedicated listener.
  """

  @behaviour Plug

  import Plug.Conn

  alias EdgeAgentWeb.Plugs.ApiTokenAuth
  alias Plug.Conn

  require Logger

  @metrics_path "/api/v1/agents/me/metrics/raw"

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
    if Application.get_env(:edge_agent, :agent_metrics_dedicated, false) do
      Bandit.start_link(
        plug: __MODULE__,
        scheme: :http,
        port: Application.fetch_env!(:edge_agent, :agent_metrics_port),
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      )
    else
      :ignore
    end
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Conn{request_path: @metrics_path} = conn, _opts) do
    conn
    |> authenticate()
    |> serve_metrics()
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
    |> halt()
  end

  defp authenticate(conn) do
    if Application.get_env(:edge_agent, :agent_metrics_auth_enabled, true) do
      ApiTokenAuth.call(conn, [])
    else
      conn
    end
  end

  defp serve_metrics(%Conn{halted: true} = conn), do: conn

  defp serve_metrics(conn) do
    case PromEx.get_metrics(EdgeAgent.PromEx) do
      :prom_ex_down ->
        Logger.warning("Attempted to fetch metrics from EdgeAgent.PromEx, but PromEx is unavailable")

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, "Service Unavailable")
        |> halt()

      metrics ->
        PromEx.ETSCronFlusher.defer_ets_flush(EdgeAgent.PromEx.__ets_cron_flusher_name__())

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, metrics)
        |> halt()
    end
  end
end
