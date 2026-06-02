defmodule EdgeAdmin.SentryTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdmin.Sentry

  defp conn_with_params(params) do
    "POST"
    |> conn("/")
    |> Map.put(:params, params)
    |> Map.put(:body_params, params)
    |> Map.put(:query_params, %{})
    |> Map.put(:path_params, %{})
  end

  test "scrub_params redacts secret-shaped string keys" do
    conn =
      conn_with_params(%{
        "api_token" => "tok-123",
        "proxy_password" => "pw-123",
        "authorization" => "Bearer top-secret",
        "proxy-authorization" => "Basic dXNlcjpwYXNz"
      })

    scrubbed = Sentry.scrub_params(conn)

    assert scrubbed["api_token"] == "*********"
    assert scrubbed["proxy_password"] == "*********"
    assert scrubbed["authorization"] == "*********"
    assert scrubbed["proxy-authorization"] == "*********"
  end

  test "scrub_params redacts secret-shaped atom keys inside nested maps" do
    conn =
      conn_with_params(%{
        payload: %{
          api_token: "tok-123",
          proxy_password: "pw-123",
          headers: %{
            "x-api-key" => "key-123",
            authorization: "Bearer top-secret"
          }
        }
      })

    scrubbed = Sentry.scrub_params(conn)

    assert scrubbed[:payload][:api_token] == "*********"
    assert scrubbed[:payload][:proxy_password] == "*********"
    assert scrubbed[:payload][:headers] == "*********"
  end
end
