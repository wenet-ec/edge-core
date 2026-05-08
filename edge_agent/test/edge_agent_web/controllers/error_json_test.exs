# edge_agent/test/edge_agent_web/controllers/error_json_test.exs
defmodule EdgeAgentWeb.Controllers.ErrorJSONTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAgentWeb.Controllers.ErrorJSON

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
  # The error code in the envelope is the canonical machine-readable handle
  # clients pattern-match on; the message is the human-readable companion.
  # ---------------------------------------------------------------------------

  describe "per-status renders" do
    test "400.json → bad_request" do
      result = render("400.json")
      assert result.error.code == "bad_request"
      assert result.error.message == "Malformed request body"
    end

    test "401.json → unauthorized" do
      result = render("401.json")
      assert result.error.code == "unauthorized"
      assert result.error.message == "Missing or invalid credentials"
    end

    test "403.json → forbidden" do
      result = render("403.json")
      assert result.error.code == "forbidden"
      assert result.error.message == "Insufficient permissions"
    end

    test "404.json → not_found" do
      result = render("404.json")
      assert result.error.code == "not_found"
      assert result.error.message == "Resource not found"
    end

    test "409.json → conflict" do
      result = render("409.json")
      assert result.error.code == "conflict"
      assert result.error.message == "Resource already exists"
    end

    test "503.json → service_unavailable" do
      result = render("503.json")
      assert result.error.code == "service_unavailable"
      assert result.error.message == "Downstream dependency unreachable"
    end
  end

  # ---------------------------------------------------------------------------
  # Catch-all — security pin. Any unrecognised template (e.g. raised
  # exceptions Phoenix didn't have a specific render for) MUST surface as a
  # generic 500-class response with no exception details leaked.
  # ---------------------------------------------------------------------------

  describe "catch-all" do
    test "unrecognised templates fall through to internal_server_error" do
      assert render("500.json").error.code == "internal_server_error"
      assert render("418.json").error.code == "internal_server_error"
      assert render("anything-else.json").error.code == "internal_server_error"
    end

    test "catch-all message is generic (no exception details leaked)" do
      result = render("500.json")
      assert result.error.message == "An unexpected error occurred"
    end
  end

  # ---------------------------------------------------------------------------
  # Envelope shape — all renders go through ResponseEnvelope.error/3, so they
  # all share the documented top-level shape.
  # ---------------------------------------------------------------------------

  describe "envelope shape" do
    test "all renders return a map with :error and :meta" do
      for template <- ~w(400.json 401.json 403.json 404.json 409.json 503.json 500.json) do
        result = render(template)

        assert result |> Map.keys() |> Enum.sort() == [:error, :meta],
               "expected #{template} to have :error and :meta at the top level"
      end
    end

    test "no template carries :details (no validation context for default errors)" do
      for template <- ~w(400.json 401.json 403.json 404.json 409.json 503.json 500.json) do
        refute Map.has_key?(render(template).error, :details),
               "expected #{template} not to include :details"
      end
    end

    test "meta carries the request_id from conn.assigns" do
      assert render("404.json").meta.request_id == "test-req-id"
    end
  end
end
