# lib/edge_admin_health/router.ex
defmodule EdgeAdminHealth.Router do
  use Plug.Router

  defmodule Health do
    @moduledoc false
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    forward(
      "/",
      to: PlugCheckup,
      init_opts:
        PlugCheckup.Options.new(
          json_encoder: Jason,
          checks: EdgeAdminHealth.checks(),
          error_code: EdgeAdminHealth.error_code(),
          timeout: :timer.seconds(5),
          pretty: false
        )
    )
  end

  plug(:match)
  plug(:dispatch)

  forward("/health", to: Health)

  match(_, do: conn)
end
