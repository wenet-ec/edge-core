# edge_agent/test/edge_agent_web/controllers/self_update_controller_test.exs
defmodule EdgeAgentWeb.Controllers.SelfUpdateControllerTest do
  use EdgeAgentWeb.ConnCase

  alias EdgeAgent.Settings

  @token "test-api-token"

  setup do
    :ok = Settings.set_api_token(@token)
    :ok
  end

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer #{@token}")

  defp with_self_update_enabled(value, fun) do
    old = Application.get_env(:edge_agent, :self_update_enabled)
    Application.put_env(:edge_agent, :self_update_enabled, value)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:edge_agent, :self_update_enabled)
      else
        Application.put_env(:edge_agent, :self_update_enabled, old)
      end
    end
  end

  describe "trigger/2 — self-update disabled" do
    test "returns 403 when self_update_enabled is false", %{conn: conn} do
      with_self_update_enabled(false, fn ->
        conn = post(authed(conn), ~p"/api/v1/self_updates/trigger")
        assert conn.status == 403
      end)
    end

    test "response body has error.code forbidden when disabled", %{conn: conn} do
      with_self_update_enabled(false, fn ->
        conn = post(authed(conn), ~p"/api/v1/self_updates/trigger")
        body = JSON.decode!(conn.resp_body)
        assert get_in(body, ["error", "code"]) == "forbidden"
      end)
    end

    test "defaults to disabled when config key is absent", %{conn: conn} do
      Application.delete_env(:edge_agent, :self_update_enabled)

      conn = post(authed(conn), ~p"/api/v1/self_updates/trigger")
      assert conn.status == 403

      # restore
      Application.delete_env(:edge_agent, :self_update_enabled)
    end
  end

  describe "trigger/2 — self-update enabled" do
    test "returns 202 when self_update_enabled is true", %{conn: conn} do
      with_self_update_enabled(true, fn ->
        conn = post(authed(conn), ~p"/api/v1/self_updates/trigger")
        assert conn.status == 202
      end)
    end

    test "response body has data.message key when enabled", %{conn: conn} do
      with_self_update_enabled(true, fn ->
        conn = post(authed(conn), ~p"/api/v1/self_updates/trigger")
        body = JSON.decode!(conn.resp_body)
        assert get_in(body, ["data", "message"])
      end)
    end

    test "response message mentions self-update triggered", %{conn: conn} do
      with_self_update_enabled(true, fn ->
        conn = post(authed(conn), ~p"/api/v1/self_updates/trigger")
        body = JSON.decode!(conn.resp_body)
        assert get_in(body, ["data", "message"]) =~ "triggered"
      end)
    end
  end
end
