# edge_agent/test/edge_agent_proxy/authentication_test.exs
defmodule EdgeAgentProxy.AuthenticationTest do
  use ExUnit.Case, async: true

  alias EdgeAgentProxy.Authentication

  test "accepts the configured proxy username and password" do
    assert Authentication.valid_credentials?("_", "secret", "secret")
  end

  test "rejects a wrong password or username" do
    refute Authentication.valid_credentials?("_", "wrong", "secret")
    refute Authentication.valid_credentials?("admin", "secret", "secret")
  end

  test "rejects missing or non-binary configured passwords" do
    refute Authentication.valid_credentials?("_", "secret", nil)
    refute Authentication.valid_credentials?("_", "secret", :invalid)
  end
end
