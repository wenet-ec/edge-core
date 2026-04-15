# edge_admin/test/edge_admin_web/plugs/assign_request_id_test.exs
defmodule EdgeAdminWeb.Plugs.AssignRequestIdTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAdminWeb.Plugs.AssignRequestId

  @opts AssignRequestId.init([])

  defp call, do: :get |> conn("/") |> AssignRequestId.call(@opts)

  describe "assigns request_id" do
    test "sets conn.assigns.request_id" do
      conn = call()
      assert Map.has_key?(conn.assigns, :request_id)
    end

    test "request_id is a non-empty string" do
      conn = call()
      assert is_binary(conn.assigns.request_id)
      assert String.length(conn.assigns.request_id) > 0
    end

    test "request_id is a valid UUID (36 chars, 4 hyphens)" do
      conn = call()
      id = conn.assigns.request_id
      assert String.length(id) == 36
      assert id |> String.split("-") |> length() == 5
    end

    test "each call generates a unique request_id" do
      id1 = call().assigns.request_id
      id2 = call().assigns.request_id
      assert id1 != id2
    end
  end

  describe "sets x-request-id response header" do
    test "x-request-id header is set" do
      conn = call()
      [header_value] = Plug.Conn.get_resp_header(conn, "x-request-id")
      assert is_binary(header_value)
    end

    test "x-request-id header matches conn.assigns.request_id" do
      conn = call()
      [header_value] = Plug.Conn.get_resp_header(conn, "x-request-id")
      assert header_value == conn.assigns.request_id
    end

    test "overwrites any existing x-request-id header" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.put_resp_header("x-request-id", "old-base64-id")
        |> AssignRequestId.call(@opts)

      [header_value] = Plug.Conn.get_resp_header(conn, "x-request-id")
      assert header_value != "old-base64-id"
    end
  end

  describe "does not halt the conn" do
    test "conn is not halted" do
      conn = call()
      refute conn.halted
    end
  end
end
