# edge_agent/test/edge_agent_web/controllers/command_execution_controller_test.exs
defmodule EdgeAgentWeb.CommandExecutionControllerTest do
  use EdgeAgentWeb.ConnCase

  @create_attrs %{
    id: "01234567-89ab-cdef-0123-456789abcdef",
    command_id: "7488a646-e31f-11e4-aace-600308960662",
    node_id: "7488a646-e31f-11e4-aace-600308960662",
    command_text: "echo hello\nls -la",
    status: "pending"
  }

  @invalid_attrs %{
    command_id: nil,
    node_id: nil,
    command_text: nil,
    status: nil
  }

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "create command_execution" do
    test "renders command_execution when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/command-executions", @create_attrs)

      assert %{"id" => id} = json_response(conn, 201)["data"]
      assert id == @create_attrs.id
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/command-executions", @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end
end
