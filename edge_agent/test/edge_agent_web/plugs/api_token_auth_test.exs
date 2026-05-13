# edge_agent/test/edge_agent_web/plugs/api_token_auth_test.exs
defmodule EdgeAgentWeb.Plugs.ApiTokenAuthTest do
  use EdgeAgentWeb.ConnCase

  alias EdgeAgent.Settings
  alias EdgeAgentWeb.Plugs.ApiTokenAuth

  defp call(conn), do: ApiTokenAuth.call(conn, ApiTokenAuth.init([]))

  # -----------------------------------------------------------------------
  # No token stored in Settings
  # -----------------------------------------------------------------------

  describe "call/2 — no token configured in Settings" do
    test "returns 401 when Settings has no api_token", %{conn: conn} do
      # Fresh sandbox — no api_token set
      conn = call(conn)
      assert conn.status == 401
      assert conn.halted
    end

    test "response body has error key", %{conn: conn} do
      conn = call(conn)
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end
  end

  # -----------------------------------------------------------------------
  # Token stored, various header scenarios
  # -----------------------------------------------------------------------

  describe "call/2 — token configured in Settings" do
    setup do
      :ok = Settings.set_api_token("secret-agent-token")
      :ok
    end

    test "correct Bearer token passes through", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer secret-agent-token")
        |> call()

      refute conn.halted
      assert conn.status != 401
    end

    test "conn is not halted on success", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer secret-agent-token")
        |> call()

      refute conn.halted
    end

    test "wrong token returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> call()

      assert conn.status == 401
      assert conn.halted
    end

    test "no Authorization header returns 401", %{conn: conn} do
      conn = call(conn)
      assert conn.status == 401
      assert conn.halted
    end

    test "wrong scheme (Basic) returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic secret-agent-token")
        |> call()

      assert conn.status == 401
      assert conn.halted
    end

    test "empty Bearer value returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> call()

      assert conn.status == 401
      assert conn.halted
    end

    test "token without Bearer prefix returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "secret-agent-token")
        |> call()

      assert conn.status == 401
      assert conn.halted
    end

    test "token comparison is exact (case-sensitive)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer SECRET-AGENT-TOKEN")
        |> call()

      assert conn.status == 401
      assert conn.halted
    end

    test "response body has error key on failure", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> call()

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "error")
    end

    test "response content-type is application/json on failure", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> call()

      assert conn |> get_resp_header("content-type") |> hd() =~ "application/json"
    end
  end
end
