# tailscale/test/test_helper.exs
ExUnit.start()

# Import Mox for mocking
Mox.defmock(Tailscale.Cli.MockClient, for: Tailscale.Behaviours.Cli)
Mox.defmock(Tailscale.Api.MockClient, for: Tailscale.Behaviours.Api)

# Configure test environment to use mocks
Application.put_env(:tailscale, :cli_client, Tailscale.Cli.MockClient)
Application.put_env(:tailscale, :api_client, Tailscale.Api.MockClient)
