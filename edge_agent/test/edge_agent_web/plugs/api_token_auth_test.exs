# edge_agent/test/edge_agent_web/plugs/api_token_auth_test.exs
defmodule EdgeAgentWeb.Plugs.ApiTokenAuthTest do
  use ExUnit.Case, async: true

  alias EdgeAgentWeb.Plugs.ApiTokenAuth

  test "extracts a Bearer token from exactly one authorization header" do
    assert {:ok, "secret-token"} = ApiTokenAuth.bearer_token(["Bearer secret-token"])
    assert {:error, :missing_token} = ApiTokenAuth.bearer_token([])
    assert {:error, :missing_token} = ApiTokenAuth.bearer_token(["Basic secret-token"])
    assert {:error, :missing_token} = ApiTokenAuth.bearer_token(["Bearer a", "Bearer b"])
  end

  test "compares tokens exactly" do
    assert ApiTokenAuth.authorized?("secret-token", "secret-token")
    refute ApiTokenAuth.authorized?("wrong-token", "secret-token")
    refute ApiTokenAuth.authorized?("SECRET-TOKEN", "secret-token")
    refute ApiTokenAuth.authorized?("secret-token", nil)
  end

  test "accepts empty Bearer value as a parsed value, but never matches a nonempty stored token" do
    assert {:ok, ""} = ApiTokenAuth.bearer_token(["Bearer "])
    refute ApiTokenAuth.authorized?("", "secret-token")
  end
end
