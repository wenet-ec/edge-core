# edge_admin/lib/edge_admin/prom_ex/server.ex
defmodule EdgeAdmin.PromEx.Server do
  @moduledoc """
  Bandit endpoint for Admin PromEx metrics.

  The normal metrics route remains mounted on the Admin API endpoint unless
  `ADMIN_METRICS_PORT` is configured. In dedicated mode this Plug serves the
  same path and authentication contract from the dedicated listener.
  """

  @behaviour Plug

  import Plug.Conn

  alias EdgeAdminWeb.Plugs.MetricsAuth
  alias Plug.Conn

  require Logger

  @metrics_path "/api/v1/admins/me/metrics/raw"

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
    if Application.get_env(:edge_admin, :admin_metrics_dedicated, false) do
      Bandit.start_link(
        plug: __MODULE__,
        scheme: :http,
        port: Application.fetch_env!(:edge_admin, :admin_metrics_port),
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
    |> MetricsAuth.call([])
    |> serve_metrics()
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
    |> halt()
  end

  defp serve_metrics(%Conn{halted: true} = conn), do: conn

  defp serve_metrics(conn) do
    case PromEx.get_metrics(EdgeAdmin.PromEx) do
      :prom_ex_down ->
        Logger.warning("Attempted to fetch metrics from EdgeAdmin.PromEx, but PromEx is unavailable")

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, "Service Unavailable")
        |> halt()

      metrics ->
        PromEx.ETSCronFlusher.defer_ets_flush(EdgeAdmin.PromEx.__ets_cron_flusher_name__())

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, metrics)
        |> halt()
    end
  end
end
