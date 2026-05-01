# edge_admin/test/test_helper.exs
# Ensure ExMachina is started
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start ExUnit with better configuration
ExUnit.start(
  # Capture log output during tests to avoid noise
  capture_log: true,
  # Enable test timeouts
  timeout: 30_000,
  # Show more detailed test output
  trace: System.get_env("TRACE_TESTS") == "true"
)

# Configure the database sandbox — Sandbox needs the real Ecto.Repo impl
# (Postgres or SQLite), not the dispatcher.
Ecto.Adapters.SQL.Sandbox.mode(Application.fetch_env!(:edge_admin, :repo_impl), :manual)
