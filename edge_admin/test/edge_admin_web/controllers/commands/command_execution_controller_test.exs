# edge_admin/test/edge_admin_web/controllers/commands/command_execution_controller_test.exs
defmodule EdgeAdminWeb.Commands.CommandExecutionControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.CommandsFixtures
  import EdgeAdmin.NodesFixtures

  alias EdgeAdmin.Commands.CommandExecution

  @update_attrs %{
    status: "completed",
    output: "$ echo hello\nhello\n$ ls -la\ntotal 8\n",
    exit_code: 0
  }
  @invalid_attrs %{status: "invalid_status"}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all command_executions with pagination", %{conn: conn} do
      conn = get(conn, ~p"/api/command-executions")

      response = json_response(conn, 200)
      assert response["data"] == []
      assert response["pagination"]["total"] == 0
      assert response["pagination"]["page"] == 1
      assert response["pagination"]["page_size"] == 20
    end

    test "lists command_executions with basic filtering", %{conn: conn} do
      # Create test data
      command_execution_fixture(%{status: "pending"})
      command_execution_fixture(%{status: "completed"})

      # Filter by status
      conn = get(conn, ~p"/api/command-executions?status=pending")

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["status"] == "pending"
      assert response["filters"] == %{"status" => "pending"}
    end

    test "lists command_executions with pagination", %{conn: conn} do
      # Create multiple executions
      command_execution_fixture()
      command_execution_fixture()
      command_execution_fixture()

      # Get first page with page_size 2
      conn = get(conn, ~p"/api/command-executions?page=1&page_size=2")

      response = json_response(conn, 200)
      assert length(response["data"]) == 2
      assert response["pagination"]["page"] == 1
      assert response["pagination"]["page_size"] == 2
      assert response["pagination"]["total"] == 3
      assert response["pagination"]["total_pages"] == 2
      assert response["pagination"]["has_next"] == true
      assert response["pagination"]["has_prev"] == false
    end

    test "lists command_executions with sorting", %{conn: conn} do
      # Create executions with different statuses
      command_execution_fixture(%{status: "pending"})
      command_execution_fixture(%{status: "completed"})

      # Sort by status descending
      conn = get(conn, ~p"/api/command-executions?sort=status:desc")

      response = json_response(conn, 200)
      statuses = Enum.map(response["data"], & &1["status"])
      # pending > completed alphabetically
      assert statuses == ["pending", "completed"]
      assert response["sort"] == ["status:desc"]
    end

    test "lists command_executions filtered by command_id", %{conn: conn} do
      command1 = command_fixture()
      command2 = command_fixture()

      execution1 = command_execution_fixture(%{command_id: command1.id})
      _execution2 = command_execution_fixture(%{command_id: command2.id})

      conn = get(conn, ~p"/api/command-executions?command_id=#{command1.id}")

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == execution1.id
      assert response["filters"] == %{"command_id" => command1.id}
    end

    test "lists command_executions filtered by node_id", %{conn: conn} do
      node1 = node_fixture()
      node2 = node_fixture()

      execution1 = command_execution_fixture(%{node_id: node1.id})
      _execution2 = command_execution_fixture(%{node_id: node2.id})

      conn = get(conn, ~p"/api/command-executions?node_id=#{node1.id}")

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["id"] == execution1.id
      assert response["filters"] == %{"node_id" => node1.id}
    end
  end

  describe "show command_execution" do
    setup [:create_command_execution]

    test "renders command_execution", %{conn: conn, command_execution: command_execution} do
      conn = get(conn, ~p"/api/command-executions/#{command_execution}")

      assert %{
               "id" => id,
               "status" => "pending",
               "target_all" => false,
               "command_id" => command_id,
               "node_id" => node_id
             } = json_response(conn, 200)["data"]

      assert id == command_execution.id
      assert command_id == command_execution.command_id
      assert node_id == command_execution.node_id
    end

    test "renders 404 when command_execution does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        get(conn, ~p"/api/command-executions/#{fake_id}")
      end)
    end
  end

  describe "update command_execution" do
    setup [:create_command_execution]

    test "renders command_execution when data is valid", %{
      conn: conn,
      command_execution: %CommandExecution{id: id} = command_execution
    } do
      conn =
        put(conn, ~p"/api/command-executions/#{command_execution}",
          command_execution: @update_attrs
        )

      assert %{"id" => ^id} = json_response(conn, 200)["data"]

      conn = get(conn, ~p"/api/command-executions/#{id}")

      assert %{
               "id" => ^id,
               "status" => "completed",
               "output" => "$ echo hello\nhello\n$ ls -la\ntotal 8\n",
               "exit_code" => 0,
               "target_all" => false
             } = json_response(conn, 200)["data"]
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      command_execution: command_execution
    } do
      conn =
        put(conn, ~p"/api/command-executions/#{command_execution}",
          command_execution: @invalid_attrs
        )

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "renders 404 when command_execution does not exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_error_sent(404, fn ->
        put(conn, ~p"/api/command-executions/#{fake_id}", command_execution: @update_attrs)
      end)
    end

    test "updates sent_at timestamp when marking as sent", %{
      conn: conn,
      command_execution: command_execution
    } do
      sent_time = ~U[2025-06-17 12:00:00Z]

      conn =
        put(conn, ~p"/api/command-executions/#{command_execution}",
          command_execution: %{status: "sent", sent_at: sent_time}
        )

      response = json_response(conn, 200)["data"]
      assert response["status"] == "sent"
      assert response["sent_at"] == "2025-06-17T12:00:00Z"
    end

    test "updates completed_at timestamp when marking as completed", %{
      conn: conn,
      command_execution: command_execution
    } do
      completed_time = ~U[2025-06-17 12:05:00Z]

      update_attrs = Map.merge(@update_attrs, %{completed_at: completed_time})

      conn =
        put(conn, ~p"/api/command-executions/#{command_execution}",
          command_execution: update_attrs
        )

      response = json_response(conn, 200)["data"]
      assert response["status"] == "completed"
      assert response["completed_at"] == "2025-06-17T12:05:00Z"
      assert response["exit_code"] == 0
    end
  end

  defp create_command_execution(_) do
    command_execution = command_execution_fixture()
    %{command_execution: command_execution}
  end
end
