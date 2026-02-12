defmodule EdgeAdminWeb.Plugs.DegradedModeTest do
  use EdgeAdminWeb.ConnCase, async: true

  import Mox
  import Plug.Conn

  alias EdgeAdminWeb.Plugs.DegradedMode

  setup :verify_on_exit!

  # Phoenix.Controller.render/3 needs params fetched + _format set — simulate the router pipeline
  defp prepared(%{conn: conn}) do
    conn
    |> fetch_query_params()
    |> put_req_header("accept", "application/json")
    |> Phoenix.Controller.accepts(["json"])
  end

  describe ":allow mode" do
    test "always passes through regardless of degraded state", ctx do
      opts = DegradedMode.init(:allow)
      conn = ctx |> prepared() |> DegradedMode.call(opts)
      refute conn.halted
    end

    test "does not call metadata at all", ctx do
      # No stub set up — if metadata were called it would raise
      opts = DegradedMode.init(:allow)
      conn = ctx |> prepared() |> DegradedMode.call(opts)
      refute conn.halted
    end
  end

  describe ":block mode — not degraded" do
    test "passes through when system is healthy", ctx do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> false end)
      opts = DegradedMode.init(:block)
      conn = ctx |> prepared() |> DegradedMode.call(opts)
      refute conn.halted
    end
  end

  describe ":block mode — degraded" do
    test "halts with 503 when system is degraded", ctx do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> true end)
      opts = DegradedMode.init(:block)
      conn = ctx |> prepared() |> DegradedMode.call(opts)
      assert conn.halted
      assert conn.status == 503
    end

    test "response body contains error detail", ctx do
      stub(EdgeAdmin.MetadataMock, :degraded?, fn -> true end)
      opts = DegradedMode.init(:block)
      conn = ctx |> prepared() |> DegradedMode.call(opts)
      body = json_response(conn, 503)
      assert get_in(body, ["errors", "detail"]) =~ "Service Unavailable"
    end
  end
end
