# edge_admin/test/test_helper.exs
# Ensure ExMachina is started
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Set up Mox for mocking
Mox.defmock(EdgeAdmin.TailscaleMock, for: EdgeAdmin.TailscaleBehaviour)

# Configure test environment to use mocks
Application.put_env(:edge_admin, :tailscale_module, EdgeAdmin.TailscaleMock)
Application.put_env(:edge_admin, :vpn_url, "http://test-vpn:8080")
Application.put_env(:edge_admin, :enrollment_key, "test-key")

# Start ExUnit with better configuration
ExUnit.start(
  # Capture log output during tests to avoid noise
  capture_log: true,
  # Enable test timeouts
  timeout: 30_000,
  # Show more detailed test output
  trace: System.get_env("TRACE_TESTS") == "true"
)

# Configure the database sandbox
Ecto.Adapters.SQL.Sandbox.mode(EdgeAdmin.Repo, :manual)
