# edge_agent/lib/edge_agent_web/controllers/derp_map_controller.ex
defmodule EdgeAgentWeb.Controllers.DerpMapController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.Vpn.DerpMapCache

  @empty %{"Regions" => %{}}

  @doc """
  DERP map reflection endpoint for the Edge VPN CLI.

  Returns the cached Core DERP map. If no Core map is available, the empty
  response lets the Edge VPN CLI use its own public-map fallback chain.

  This endpoint is set as DERP_MAP_URLS in the agent start script so the Edge
  VPN CLI does not need to fetch Core map sources on every connection attempt.
  """
  def show(conn, _params) do
    map = DerpMapCache.get() || @empty
    json(conn, map)
  end
end
