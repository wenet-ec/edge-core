# edge_agent/lib/edge_agent_health/router.ex
defmodule EdgeAgentHealth.Router do
  @moduledoc """
  Plug router for the edge agent's full readiness endpoints. Mounted at
  `/health`, `/healthz`, and `/readyz` by `EdgeAgentWeb.Endpoint`. Delegates to
  `PlugCheckup` with the check list from `EdgeAgentHealth.checks/0`. Returns
  200 if every check passes, 503 (`EdgeAgentHealth.error_code/0`) otherwise.
  """

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
          pretty: true
        )
    )
  end

  plug(:match)
  plug(:dispatch)

  forward("/health", to: Health)
  forward("/healthz", to: Health)
  forward("/readyz", to: Health)

  match(_, do: conn)
end
