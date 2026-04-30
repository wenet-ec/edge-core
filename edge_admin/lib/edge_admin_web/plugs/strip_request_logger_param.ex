# edge_admin/lib/edge_admin_web/plugs/strip_request_logger_param.ex
defmodule EdgeAdminWeb.Plugs.StripRequestLoggerParam do
  @moduledoc """
  Removes the `request_logger` query parameter from the conn after
  `Phoenix.LiveDashboard.RequestLogger` has consumed it.

  ## Why

  LiveDashboard's RequestLogger appends `?request_logger=<token>` to URLs so it
  can correlate logs to a browser session. The token is read by the
  `RequestLogger` plug and stashed in a cookie; the URL param itself has done
  its job by that point.

  However, downstream OpenApiSpex `CastAndValidate` enforces strict schemas and
  rejects unknown query parameters. Since `request_logger` isn't part of any
  documented API surface, every API request linked from LiveDashboard 400s with
  `Unexpected field: request_logger`.

  Stripping the param after RequestLogger has run keeps both features honest:
  the logger still works (cookie is set), and the API spec stays strict.

  ## Placement

  Mount this plug **after** `Phoenix.LiveDashboard.RequestLogger` and **before**
  the router. The endpoint pipeline is the right place.
  """

  @behaviour Plug

  @param "request_logger"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{query_params: %Plug.Conn.Unfetched{}} = conn, _opts) do
    # Query params not yet fetched — nothing to strip yet. RequestLogger fetches
    # them itself, so by the time we run this it'll usually be a real map.
    conn
  end

  def call(%Plug.Conn{query_params: %{@param => _}} = conn, _opts) do
    %{
      conn
      | query_params: Map.delete(conn.query_params, @param),
        params: Map.delete(conn.params, @param),
        query_string: rebuild_query_string(conn.query_params)
    }
  end

  def call(conn, _opts), do: conn

  defp rebuild_query_string(query_params) do
    query_params
    |> Map.delete(@param)
    |> URI.encode_query()
  end
end
