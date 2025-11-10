# edge_admin/test/edge_admin_web/controllers/commands/command_execution_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.CommandsFixtures
  import EdgeAdmin.NodesFixtures

  @update_attrs %{
    status: "completed",
    output: "$ echo hello\nhello\n",
    exit_code: 0
  }
  @invalid_attrs %{status: "invalid_status"}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists command executions with basic pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/command_executions")

      response = json_response(conn, 200)
      assert response["data"] == []
      assert response["pagination"]["total"] == 0
    end

    test "supports filtering and sorting", %{conn: conn} do
      command_execution_fixture(%{status: "pending"})
      command_execution_fixture(%{status: "completed"})

      # Test filtering
      conn = get(conn, ~p"/api/command_executions?status=pending")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["status"] == "pending"
      assert response["filters"] == %{"status" => "pending"}

      # Test sorting
      conn = get(conn, ~p"/api/command_executions?sort=status:desc")
      response = json_response(conn, 200)

      statuses = Enum.map(response["data"], & &1["status"])
      assert statuses == ["pending", "completed"]
    end

    test "filters by command_id and node_id", %{conn: conn} do
      command1 = command_fixture()
      node1 = node_fixture()

      execution1 = command_execution_fixture(%{command_id: command1.id})
      execution2 = command_execution_fixture(%{node_id: node1.id})

      # Filter by command_id
      conn = get(conn, ~p"/api/command_executions?command_id=#{command1.id}")
      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == execution1.id

      # Filter by node_id
      conn = get(conn, ~p"/api/command_executions?node_id=#{node1.id}")
      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == execution2.id
    end

    test "includes command_text in response", %{conn: conn} do
      command = command_fixture(%{command_text: "echo hello world"})
      command_execution = command_execution_fixture(%{command: command})

      conn = get(conn, ~p"/api/command_executions/#{command_execution}")

      response = json_response(conn, 200)["data"]
      assert response["id"] == command_execution.id
      assert response["command_text"] == "echo hello world"
    end

    test "returns command execution by ID", %{conn: conn} do
      command_execution = command_execution_fixture()
      conn = get(conn, ~p"/api/command_executions/#{command_execution}")

      response = json_response(conn, 200)["data"]
      assert response["id"] == command_execution.id
      assert response["status"] == "pending"
      # Ensure command_text is present
      assert is_binary(response["command_text"])
    end
  end

  describe "show command_execution" do
    test "returns command execution by ID", %{conn: conn} do
      command_execution = command_execution_fixture()
      conn = get(conn, ~p"/api/command_executions/#{command_execution}")

      response = json_response(conn, 200)["data"]
      assert response["id"] == command_execution.id
      assert response["status"] == "pending"
    end

    test "returns 404 for non-existent execution", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/command_executions/#{fake_id}")
      end)
    end
  end

  describe "delete command_execution" do
    test "deletes chosen command execution", %{conn: conn} do
      command_execution = command_execution_fixture()
      conn = delete(conn, ~p"/api/command_executions/#{command_execution}")
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/command_executions/#{command_execution}")
      end)
    end

    test "returns 404 for non-existent command execution", %{conn: conn} do
      assert_error_sent(404, fn ->
        delete(conn, ~p"/api/command_executions/00000000-0000-0000-0000-000000000000")
      end)
    end
  end
end
