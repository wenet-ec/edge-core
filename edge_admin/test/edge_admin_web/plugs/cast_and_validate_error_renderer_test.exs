# edge_admin/test/edge_admin_web/plugs/cast_and_validate_error_renderer_test.exs
defmodule EdgeAdminWeb.Plugs.CastAndValidateErrorRendererTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer

  # Build a minimal fake OpenApiSpex.Cast.Error so we don't depend on the full
  # cast pipeline. path_to_string/1 only needs %{path: [...]} and the error
  # needs to_string/1 to produce a human-readable message.
  defp fake_error(path, message) do
    %OpenApiSpex.Cast.Error{path: path, reason: :invalid_type, meta: %{message: message}}
  end

  defp build_conn do
    conn = conn(:post, "/api/v1/clusters")

    conn
    |> Plug.Conn.assign(:request_id, "test-request-id")
    |> Plug.Conn.fetch_query_params()
  end

  defp call(errors), do: CastAndValidateErrorRenderer.call(build_conn(), errors)

  defp decoded(conn), do: JSON.decode!(conn.resp_body)

  # -----------------------------------------------------------------------
  # HTTP status
  # -----------------------------------------------------------------------

  describe "HTTP status" do
    test "returns 400 (not 422)" do
      conn = call([fake_error(["name"], "Invalid type")])
      assert conn.status == 400
    end

    test "response is halted / sent" do
      conn = call([fake_error(["name"], "Invalid type")])
      assert conn.state == :sent
    end
  end

  # -----------------------------------------------------------------------
  # Content-Type
  # -----------------------------------------------------------------------

  describe "Content-Type" do
    test "sets application/json content type" do
      conn = call([fake_error(["name"], "Invalid type")])
      [ct] = Plug.Conn.get_resp_header(conn, "content-type")
      assert ct =~ "application/json"
    end
  end

  # -----------------------------------------------------------------------
  # Envelope shape
  # -----------------------------------------------------------------------

  describe "envelope shape" do
    test "body has top-level error key" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      assert Map.has_key?(body, "error")
    end

    test "body has top-level meta key" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      assert Map.has_key?(body, "meta")
    end

    test "error.code is bad_request" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      assert get_in(body, ["error", "code"]) == "bad_request"
    end

    test "error.message is Invalid request parameters" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      assert get_in(body, ["error", "message"]) == "Invalid request parameters"
    end

    test "error.details is a map" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      assert is_map(get_in(body, ["error", "details"]))
    end
  end

  # -----------------------------------------------------------------------
  # Leading slash stripping
  # -----------------------------------------------------------------------

  describe "leading slash stripping" do
    test "field key has no leading slash" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      details = get_in(body, ["error", "details"])
      refute Map.has_key?(details, "/name")
      assert Map.has_key?(details, "name")
    end

    test "nested path strips only the leading slash" do
      body = [fake_error(["address", "street"], "is required")] |> call() |> decoded()
      details = get_in(body, ["error", "details"])
      assert Map.has_key?(details, "address/street")
    end

    test "top-level empty path becomes empty string key" do
      body = [fake_error([], "top-level error")] |> call() |> decoded()
      details = get_in(body, ["error", "details"])
      assert Map.has_key?(details, "")
    end
  end

  # -----------------------------------------------------------------------
  # Error grouping
  # -----------------------------------------------------------------------

  describe "error grouping" do
    test "single error on a field produces list with one message" do
      body = [fake_error(["name"], "Invalid type")] |> call() |> decoded()
      messages = get_in(body, ["error", "details", "name"])
      assert is_list(messages)
      assert length(messages) == 1
    end

    test "multiple errors on the same field are grouped into one list" do
      errors = [
        fake_error(["name"], "Invalid type"),
        fake_error(["name"], "Invalid format")
      ]

      body = errors |> call() |> decoded()
      messages = get_in(body, ["error", "details", "name"])
      assert length(messages) == 2
    end

    test "errors on different fields produce separate keys" do
      errors = [
        fake_error(["name"], "Invalid type"),
        fake_error(["ipv4_range"], "Invalid format")
      ]

      body = errors |> call() |> decoded()
      details = get_in(body, ["error", "details"])
      assert Map.has_key?(details, "name")
      assert Map.has_key?(details, "ipv4_range")
    end
  end

  # -----------------------------------------------------------------------
  # Single error (non-list) convenience clause
  # -----------------------------------------------------------------------

  describe "single error (non-list) input" do
    test "wraps a single error into a list and processes normally" do
      conn = CastAndValidateErrorRenderer.call(build_conn(), fake_error(["name"], "Invalid type"))
      body = decoded(conn)
      assert conn.status == 400
      assert get_in(body, ["error", "code"]) == "bad_request"
      assert Map.has_key?(get_in(body, ["error", "details"]), "name")
    end
  end
end
