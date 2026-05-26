# edge_admin/test/edge_admin_web/controllers/error_json_test.exs
defmodule EdgeAdminWeb.Controllers.ErrorJSONTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdminWeb.Controllers.ErrorJSON

  defp fake_conn do
    :get
    |> conn("/")
    |> Plug.Conn.assign(:request_id, "test-req-id")
  end

  defp render(template) do
    ErrorJSON.render(template, %{conn: fake_conn()})
  end

  # ---------------------------------------------------------------------------
  # Per-status mappings — Phoenix dispatches on `<status>.json` template name.
  # ---------------------------------------------------------------------------

  describe "per-status renders" do
    test "400.json → bad_request" do
      result = render("400.json")
      assert result.error.code == "bad_request"
      assert result.error.message == "Bad Request"
    end

    test "401.json → unauthorized" do
      result = render("401.json")
      assert result.error.code == "unauthorized"
      assert result.error.message == "Unauthorized"
    end

    test "403.json → forbidden" do
      result = render("403.json")
      assert result.error.code == "forbidden"
      assert result.error.message == "Forbidden"
    end

    test "404.json → not_found" do
      result = render("404.json")
      assert result.error.code == "not_found"
      assert result.error.message == "Resource not found"
    end

    test "409.json → conflict" do
      result = render("409.json")
      assert result.error.code == "conflict"
      assert result.error.message == "Conflict"
    end

    test "500.json → internal_server_error" do
      result = render("500.json")
      assert result.error.code == "internal_server_error"
      assert result.error.message == "Internal Server Error"
    end

    test "503.json → service_unavailable" do
      result = render("503.json")
      assert result.error.code == "service_unavailable"
      assert result.error.message == "Service Unavailable"
    end

    test "503_degraded_mode.json → degraded_mode" do
      result = render("503_degraded_mode.json")
      assert result.error.code == "degraded_mode"
    end
  end

  # ---------------------------------------------------------------------------
  # Catch-all — any unrecognised template (e.g. 413 from Plug.Parsers) MUST
  # surface as a generic internal_server_error with no exception details leaked.
  # Without this clause, Phoenix raises FunctionClauseError and Bandit returns
  # an empty 500, which breaks agent retry classification.
  # ---------------------------------------------------------------------------

  describe "catch-all" do
    test "unrecognised templates fall through to internal_server_error" do
      assert render("413.json").error.code == "internal_server_error"
      assert render("418.json").error.code == "internal_server_error"
      assert render("anything-else.json").error.code == "internal_server_error"
    end

    test "catch-all message is generic (no exception details leaked)" do
      result = render("413.json")
      assert result.error.message == "An unexpected error occurred"
    end
  end

  # ---------------------------------------------------------------------------
  # Envelope shape — all renders go through ResponseEnvelope.error/3.
  # ---------------------------------------------------------------------------

  describe "envelope shape" do
    test "all renders return a map with :error and :meta" do
      for template <- ~w(400.json 401.json 403.json 404.json 409.json 500.json 503.json) do
        result = render(template)

        assert result |> Map.keys() |> Enum.sort() == [:error, :meta],
               "expected #{template} to have :error and :meta at the top level"
      end
    end

    test "no template carries :details (no validation context for default errors)" do
      for template <- ~w(400.json 401.json 403.json 404.json 409.json 500.json 503.json) do
        refute Map.has_key?(render(template).error, :details),
               "expected #{template} not to include :details"
      end
    end

    test "meta carries the request_id from conn.assigns" do
      assert render("404.json").meta.request_id == "test-req-id"
    end
  end
end
