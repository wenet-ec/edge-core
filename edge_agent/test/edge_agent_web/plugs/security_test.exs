# edge_agent/test/edge_agent_web/plugs/security_test.exs
defmodule EdgeAgentWeb.Plugs.SecurityTest do
  use ExUnit.Case, async: true

  alias EdgeAgentWeb.Plugs.Security

  test "builds the restrictive default CSP" do
    policy = Security.content_security_policy(false)

    for directive <- [
          "default-src 'none'",
          "form-action 'self'",
          "media-src 'self'",
          "img-src 'self' data:",
          "script-src 'self'",
          "font-src 'self'",
          "connect-src 'self'",
          "style-src 'self' 'unsafe-inline'",
          "frame-src 'self'"
        ] do
      assert policy =~ directive
    end

    refute policy =~ "unsafe-eval"
  end

  test "allows unsafe script directives only when explicitly enabled" do
    policy = Security.content_security_policy(true)
    assert policy =~ "script-src 'self' 'unsafe-eval' 'unsafe-inline'"
  end
end
