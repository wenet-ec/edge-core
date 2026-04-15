# edge_admin/test/edge_admin_web/controllers/fallback_controller_test.exs
defmodule EdgeAdminWeb.Controllers.FallbackControllerTest do
  use EdgeAdminWeb.ConnCase, async: true

  import Plug.Conn

  alias EdgeAdminWeb.Controllers.FallbackController

  # FallbackController.call/2 uses Phoenix.Controller.render/3 which needs
  # conn.params fetched and the response format negotiated.
  defp prepared(%{conn: conn}) do
    conn
    |> fetch_query_params()
    |> put_req_header("accept", "application/json")
    |> Phoenix.Controller.accepts(["json"])
  end

  defp call(ctx, error), do: FallbackController.call(prepared(ctx), error)

  defp body(conn), do: json_response(conn, conn.status)

  describe "{:error, %Ecto.Changeset{}} — 422 Unprocessable Entity" do
    test "returns 422", ctx do
      cs = Ecto.Changeset.add_error(%Ecto.Changeset{}, :name, "can't be blank")
      conn = call(ctx, {:error, cs})
      assert conn.status == 422
    end

    test "body has error.code = validation_failed", ctx do
      cs =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.validate_required([:name])

      conn = call(ctx, {:error, cs})
      body = body(conn)
      assert get_in(body, ["error", "code"]) == "validation_failed"
    end

    test "body has error.details with field messages", ctx do
      cs =
        {%{}, %{name: :string}}
        |> Ecto.Changeset.cast(%{}, [:name])
        |> Ecto.Changeset.validate_required([:name])

      conn = call(ctx, {:error, cs})
      body = body(conn)
      assert Map.has_key?(get_in(body, ["error", "details"]), "name")
    end
  end

  describe "{:error, :not_found} — 404 Not Found" do
    test "returns 404", ctx do
      conn = call(ctx, {:error, :not_found})
      assert conn.status == 404
    end

    test "body has error.code = not_found", ctx do
      conn = call(ctx, {:error, :not_found})
      assert get_in(body(conn), ["error", "code"]) == "not_found"
    end

    test "body has error.message mentioning not found", ctx do
      conn = call(ctx, {:error, :not_found})
      assert get_in(body(conn), ["error", "message"]) =~ "not found"
    end
  end

  describe "{:error, :forbidden} — 403 Forbidden" do
    test "returns 403", ctx do
      conn = call(ctx, {:error, :forbidden})
      assert conn.status == 403
    end

    test "body has error.code = forbidden", ctx do
      conn = call(ctx, {:error, :forbidden})
      assert get_in(body(conn), ["error", "code"]) == "forbidden"
    end

    test "body has error.message = Forbidden", ctx do
      conn = call(ctx, {:error, :forbidden})
      assert get_in(body(conn), ["error", "message"]) == "Forbidden"
    end
  end

  describe "{:error, :unauthorized} — 401 Unauthorized" do
    test "returns 401", ctx do
      conn = call(ctx, {:error, :unauthorized})
      assert conn.status == 401
    end

    test "body has error.code = unauthorized", ctx do
      conn = call(ctx, {:error, :unauthorized})
      assert get_in(body(conn), ["error", "code"]) == "unauthorized"
    end

    test "body has error.message = Unauthorized", ctx do
      conn = call(ctx, {:error, :unauthorized})
      assert get_in(body(conn), ["error", "message"]) == "Unauthorized"
    end
  end

  describe "{:error, :conflict} — 409 Conflict (generic)" do
    test "returns 409", ctx do
      conn = call(ctx, {:error, :conflict})
      assert conn.status == 409
    end

    test "body has error.code = conflict", ctx do
      conn = call(ctx, {:error, :conflict})
      assert get_in(body(conn), ["error", "code"]) == "conflict"
    end

    test "body has error.message = Conflict", ctx do
      conn = call(ctx, {:error, :conflict})
      assert get_in(body(conn), ["error", "message"]) == "Conflict"
    end
  end

  describe "{:error, {:conflict, reason}} — 409 Conflict with reason" do
    test "returns 409", ctx do
      conn = call(ctx, {:error, {:conflict, "cannot delete cluster with active nodes"}})
      assert conn.status == 409
    end

    test "body error.message contains the specific reason", ctx do
      conn = call(ctx, {:error, {:conflict, "cannot delete cluster with active nodes"}})
      assert get_in(body(conn), ["error", "message"]) == "cannot delete cluster with active nodes"
    end
  end

  describe "{:error, :service_unavailable} — 503 Service Unavailable" do
    test "returns 503", ctx do
      conn = call(ctx, {:error, :service_unavailable})
      assert conn.status == 503
    end

    test "body has error.code = service_unavailable", ctx do
      conn = call(ctx, {:error, :service_unavailable})
      assert get_in(body(conn), ["error", "code"]) == "service_unavailable"
    end

    test "body has error.message = Service Unavailable", ctx do
      conn = call(ctx, {:error, :service_unavailable})
      assert get_in(body(conn), ["error", "message"]) == "Service Unavailable"
    end
  end

  describe "{:error, :bad_request} — 400 Bad Request" do
    test "returns 400", ctx do
      conn = call(ctx, {:error, :bad_request})
      assert conn.status == 400
    end

    test "body has error.code = bad_request", ctx do
      conn = call(ctx, {:error, :bad_request})
      assert get_in(body(conn), ["error", "code"]) == "bad_request"
    end

    test "body has error.message = Bad Request", ctx do
      conn = call(ctx, {:error, :bad_request})
      assert get_in(body(conn), ["error", "message"]) == "Bad Request"
    end
  end

  describe "{:error, unknown_term} — 500 catch-all" do
    test "returns 500 for unexpected atom", ctx do
      conn = call(ctx, {:error, :something_unexpected})
      assert conn.status == 500
    end

    test "returns 500 for unexpected map", ctx do
      conn = call(ctx, {:error, %{some: "weird error"}})
      assert conn.status == 500
    end

    test "returns 500 for bare binary string (no longer a named error)", ctx do
      conn = call(ctx, {:error, "untagged error string"})
      assert conn.status == 500
    end

    test "body has error.code = internal_server_error", ctx do
      conn = call(ctx, {:error, :something_unexpected})
      assert get_in(body(conn), ["error", "code"]) == "internal_server_error"
    end

    test "body has error.message = Internal Server Error", ctx do
      conn = call(ctx, {:error, :something_unexpected})
      assert get_in(body(conn), ["error", "message"]) == "Internal Server Error"
    end
  end
end
