# edge_admin/lib/edge_admin_web/plugs/degraded_mode.ex
defmodule EdgeAdminWeb.Plugs.DegradedMode do
  @moduledoc """
  Plug for enforcing degraded mode restrictions.

  When the system is in degraded mode (capacity exceeded), certain write
  operations are blocked to maintain consistency while allowing reads
  and safe operations to continue.

  Returns 503 Service Unavailable during degraded mode.
  Clients can check the metadata endpoint (/api/admins/self) for degraded status.

  ## Usage in controllers

      # Block actions during degraded mode
      plug EdgeAdminWeb.Plugs.DegradedMode, :block when action in [:create, :delete]

      # Explicitly allow actions (documentation only - this is the default)
      plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show]

  ## Modes

  - `:block` - Returns 503 Service Unavailable during degraded mode
  - `:allow` - No-op (default behavior, for documentation/clarity)
  """

  import Plug.Conn
  import Phoenix.Controller

  alias EdgeAdmin.Admins.Metadata

  def init(mode), do: mode

  def call(conn, :allow) do
    # No-op - explicitly allowed (for documentation)
    conn
  end

  def call(conn, :block) do
    if Metadata.degraded?() do
      conn
      |> put_status(:service_unavailable)
      |> put_view(json: EdgeAdminWeb.Controllers.ErrorJSON)
      |> render(:"503")
      |> halt()
    else
      conn
    end
  end
end
