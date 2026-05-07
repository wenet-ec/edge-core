# edge_admin/lib/edge_admin_web/plugs/degraded_mode.ex
defmodule EdgeAdminWeb.Plugs.DegradedMode do
  @moduledoc """
  Plug for enforcing degraded mode restrictions.

  When the system is in degraded mode (capacity exceeded), certain write
  operations are blocked to maintain consistency while allowing reads
  and safe operations to continue.

  Returns 503 Service Unavailable during degraded mode.
  Clients can check the metadata endpoint (/api/v1/admins/me) for degraded status.

  ## Usage in controllers

      # Block actions during degraded mode
      plug EdgeAdminWeb.Plugs.DegradedMode, :block when action in [:create, :delete]

      # Explicitly allow actions (documentation only - this is the default)
      plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show]

  ## Modes

  - `:block` - Returns 503 Service Unavailable during degraded mode
  - `:allow` - No-op (default behavior, for documentation/clarity)
  """

  import Phoenix.Controller
  import Plug.Conn

  # Compile-time dispatch: the metadata module is baked into the plug at compile
  # time via `compile_env`. Tests override it by setting `:metadata_module` in
  # config/test.exs before compilation. Runtime swaps are NOT supported — change
  # the config and recompile.
  @metadata_module Application.compile_env(:edge_admin, :metadata_module, EdgeAdmin.Admins.Metadata)
  @compile {:no_warn_undefined, @metadata_module}

  def init(mode), do: mode

  def call(conn, :allow) do
    # No-op - explicitly allowed (for documentation)
    conn
  end

  def call(conn, :block) do
    if @metadata_module.degraded?() do
      conn
      |> put_status(:service_unavailable)
      |> put_view(json: EdgeAdminWeb.Controllers.ErrorJSON)
      |> render(:"503_degraded_mode")
      |> halt()
    else
      conn
    end
  end
end
