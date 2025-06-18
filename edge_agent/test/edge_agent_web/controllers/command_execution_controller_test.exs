# edge_agent/test/edge_agent_web/controllers/command_execution_controller_test.exs
defmodule EdgeAgentWeb.CommandExecutionControllerTest do
  use EdgeAgentWeb.ConnCase

  @create_attrs %{
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

      # Verify the created command execution has correct data
      assert %{
               "id" => ^id,
               "command_id" => "7488a646-e31f-11e4-aace-600308960662",
               "node_id" => "7488a646-e31f-11e4-aace-600308960662",
               "command_text" => "echo hello\nls -la",
               "status" => "pending",
               "output" => nil,
               "exit_code" => nil,
               "inserted_at" => _,
               "updated_at" => _
             } = json_response(conn, 201)["data"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/command-executions", @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "handles EdgeAdmin format (direct params without nesting)", %{conn: conn} do
      # This tests the format EdgeAdmin will send
      conn = post(conn, ~p"/api/command-executions", @create_attrs)

      assert %{"id" => _id} = json_response(conn, 201)["data"]
    end
  end
end
