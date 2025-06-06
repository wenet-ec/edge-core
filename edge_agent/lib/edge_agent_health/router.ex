# edge_agent/lib/edge_agent_health/router.ex
defmodule EdgeAgentHealth.Router do
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
          checks: EdgeAgentHealth.checks(),
          error_code: EdgeAgentHealth.error_code(),
          timeout: to_timeout(second: 5),
          pretty: false
        )
    )
  end

  plug(:match)
  plug(:dispatch)

  forward("/health", to: Health)

  match(_, do: conn)
end
