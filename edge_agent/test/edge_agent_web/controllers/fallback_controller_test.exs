# edge_agent/test/edge_agent_web/controllers/fallback_controller_test.exs
defmodule EdgeAgentWeb.Controllers.FallbackControllerTest do
  use EdgeAgentWeb.ConnCase

  import Ecto.Changeset

  alias EdgeAgentWeb.Controllers.FallbackController

  defp call(conn, result) do
    conn
    |> fetch_query_params()
    |> Phoenix.Controller.accepts(["json"])
    |> FallbackController.call(result)
  end

  defp empty_changeset do
    {%{}, %{name: :string}}
    |> cast(%{}, [:name])
    |> validate_required([:name])
  end

  # -----------------------------------------------------------------------
  # Clause 1: Ecto.Changeset → 422
  # -----------------------------------------------------------------------

  describe "call/2 — changeset → 422" do
    test "returns 422 for changeset error", %{conn: conn} do
      conn = call(conn, {:error, empty_changeset()})
      assert conn.status == 422
    end

    test "response has errors key", %{conn: conn} do
      conn = call(conn, {:error, empty_changeset()})
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "errors")
    end
  end

  # -----------------------------------------------------------------------
  # Clause 2: :not_found → 404
  # -----------------------------------------------------------------------

  describe "call/2 — :not_found → 404" do
    test "returns 404", %{conn: conn} do
      conn = call(conn, {:error, :not_found})
      assert conn.status == 404
    end

    test "response has errors.detail key", %{conn: conn} do
      conn = call(conn, {:error, :not_found})
      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["errors", "detail"])
    end
  end

  # -----------------------------------------------------------------------
  # Clause 3: :forbidden → 403
  # -----------------------------------------------------------------------

  describe "call/2 — :forbidden → 403" do
    test "returns 403", %{conn: conn} do
      conn = call(conn, {:error, :forbidden})
      assert conn.status == 403
    end

    test "response has errors.detail", %{conn: conn} do
      conn = call(conn, {:error, :forbidden})
      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["errors", "detail"])
    end
  end

  # -----------------------------------------------------------------------
  # Clause 4: :unauthorized → 401
  # -----------------------------------------------------------------------

  describe "call/2 — :unauthorized → 401" do
    test "returns 401", %{conn: conn} do
      conn = call(conn, {:error, :unauthorized})
      assert conn.status == 401
    end
  end

  # -----------------------------------------------------------------------
  # Clause 5: :conflict → 409
  # -----------------------------------------------------------------------

  describe "call/2 — :conflict → 409" do
    test "returns 409", %{conn: conn} do
      conn = call(conn, {:error, :conflict})
      assert conn.status == 409
    end
  end

  # -----------------------------------------------------------------------
  # Clause 6: {:conflict, reason} → 409 with specific reason
  # -----------------------------------------------------------------------

  describe "call/2 — {:conflict, reason} → 409 with reason" do
    test "returns 409", %{conn: conn} do
      conn = call(conn, {:error, {:conflict, "cannot delete with active nodes"}})
      assert conn.status == 409
    end

    test "response errors.detail contains the specific reason", %{conn: conn} do
      conn = call(conn, {:error, {:conflict, "cannot delete with active nodes"}})
      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["errors", "detail"]) == "cannot delete with active nodes"
    end
  end

  # -----------------------------------------------------------------------
  # Clause 7: {:unprocessable, reason} → 422 with reason
  # -----------------------------------------------------------------------

  describe "call/2 — {:unprocessable, reason} → 422 with reason" do
    test "returns 422", %{conn: conn} do
      conn = call(conn, {:error, {:unprocessable, "node is already in this cluster"}})
      assert conn.status == 422
    end

    test "body errors.detail contains the specific reason", %{conn: conn} do
      conn = call(conn, {:error, {:unprocessable, "node is already in this cluster"}})
      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["errors", "detail"]) == "node is already in this cluster"
    end
  end

  # -----------------------------------------------------------------------
  # Clause 8: :service_unavailable → 503
  # -----------------------------------------------------------------------

  describe "call/2 — :service_unavailable → 503" do
    test "returns 503", %{conn: conn} do
      conn = call(conn, {:error, :service_unavailable})
      assert conn.status == 503
    end
  end

  # -----------------------------------------------------------------------
  # Clause 9: :bad_request → 400
  # -----------------------------------------------------------------------

  describe "call/2 — :bad_request → 400" do
    test "returns 400", %{conn: conn} do
      conn = call(conn, {:error, :bad_request})
      assert conn.status == 400
    end
  end

  # -----------------------------------------------------------------------
  # Clause 10: catch-all → 500
  # -----------------------------------------------------------------------

  describe "call/2 — catch-all → 500" do
    test "unknown atom returns 500", %{conn: conn} do
      conn = call(conn, {:error, :some_unknown_atom})
      assert conn.status == 500
    end

    test "map error returns 500", %{conn: conn} do
      conn = call(conn, {:error, %{some: :map}})
      assert conn.status == 500
    end

    test "returns 500 for bare binary string (no longer a named error)", %{conn: conn} do
      conn = call(conn, {:error, "untagged error string"})
      assert conn.status == 500
    end

    test "500 response has errors.detail", %{conn: conn} do
      conn = call(conn, {:error, :some_unknown_atom})
      body = Jason.decode!(conn.resp_body)
      assert get_in(body, ["errors", "detail"])
    end
  end
end
