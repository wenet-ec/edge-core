# edge_agent/lib/edge_agent_web/controllers/derp_map_controller.ex
defmodule EdgeAgentWeb.Controllers.DerpMapController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.Vpn.DerpMapCache

  @empty %{"Regions" => %{}}

  @doc """
  DERP map reflection endpoint for netclient.

  Returns the cached DERP map fetched from the configured map server.
  If no map server is configured or the last fetch failed, returns an empty
  regions map — netclient skips the overlay and falls back to Tailscale.

  This endpoint is set as DERP_MAP_URLS in the agent start script so netclient
  can fetch a fresh map on every DERP connect attempt without blocking on a
  live outbound request.
  """
  def show(conn, _params) do
    map = DerpMapCache.get() || @empty
    json(conn, map)
  end
end
