# edge_admin/test/edge_admin_web/controllers/commands/command_execution_controller_test.exs
defmodule EdgeAdminWeb.Commands.CommandExecutionControllerTest do
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
      conn = get(conn, ~p"/api/command-executions")

      response = json_response(conn, 200)
      assert response["data"] == []
      assert response["pagination"]["total"] == 0
    end

    test "supports filtering and sorting", %{conn: conn} do
      command_execution_fixture(%{status: "pending"})
      command_execution_fixture(%{status: "completed"})

      # Test filtering
      conn = get(conn, ~p"/api/command-executions?status=pending")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["status"] == "pending"
      assert response["filters"] == %{"status" => "pending"}

      # Test sorting
      conn = get(conn, ~p"/api/command-executions?sort=status:desc")
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
      conn = get(conn, ~p"/api/command-executions?command_id=#{command1.id}")
      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == execution1.id

      # Filter by node_id
      conn = get(conn, ~p"/api/command-executions?node_id=#{node1.id}")
      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == execution2.id
    end
  end

  describe "show command_execution" do
    test "returns command execution by ID", %{conn: conn} do
      command_execution = command_execution_fixture()
      conn = get(conn, ~p"/api/command-executions/#{command_execution}")

      response = json_response(conn, 200)["data"]
      assert response["id"] == command_execution.id
      assert response["status"] == "pending"
    end

    test "returns 404 for non-existent execution", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/command-executions/#{fake_id}")
      end)
    end
  end

  describe "update command_execution" do
    test "updates execution with valid data", %{conn: conn} do
      command_execution = command_execution_fixture()

      conn =
        put(conn, ~p"/api/command-executions/#{command_execution}",
          command_execution: @update_attrs
        )

      response = json_response(conn, 200)["data"]
      assert response["status"] == "completed"
      assert response["output"] == "$ echo hello\nhello\n"
      assert response["exit_code"] == 0
    end

    test "handles validation errors", %{conn: conn} do
      command_execution = command_execution_fixture()

      conn =
        put(conn, ~p"/api/command-executions/#{command_execution}",
          command_execution: @invalid_attrs
        )

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns 404 for non-existent execution", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        put(conn, ~p"/api/command-executions/#{fake_id}", command_execution: @update_attrs)
      end)
    end

    test "updates timestamps correctly", %{conn: conn} do
      command_execution = command_execution_fixture()
      completed_time = ~U[2025-06-17 12:05:00Z]

      attrs = Map.merge(@update_attrs, %{completed_at: completed_time})

      conn = put(conn, ~p"/api/command-executions/#{command_execution}", command_execution: attrs)

      response = json_response(conn, 200)["data"]
      assert response["status"] == "completed"
      assert response["completed_at"] == "2025-06-17T12:05:00Z"
    end
  end
end
