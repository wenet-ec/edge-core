# edge_agent/test/test_helper.exs
ExUnit.start(
  capture_log: true,
  timeout: 30_000,
  trace: System.get_env("TRACE_TESTS") == "true"
)

Ecto.Adapters.SQL.Sandbox.mode(EdgeAgent.Repo, :manual)
