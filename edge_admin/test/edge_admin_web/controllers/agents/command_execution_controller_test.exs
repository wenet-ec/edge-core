# edge_admin/test/edge_admin_web/controllers/agents/command_execution_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionControllerTest do
  use EdgeAdminWeb.ConnCase

  import EdgeAdmin.NodesFixtures
  import EdgeAdmin.CommandsFixtures

  alias EdgeAdmin.Commands

  setup %{conn: conn} do
    # Create node with api_token for authentication
    node = node_fixture(%{api_token: "test-api-token-123"})

    # Authenticated connection (agent)
    auth_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token-123")

    {:ok, conn: conn, auth_conn: auth_conn, node: node}
  end

  describe "GET /api/agents/command_executions (command sync)" do
    test "lists sent command executions for authenticated node", %{auth_conn: conn, node: node} do
      # Create command
      command = command_fixture()

      # Create command executions with different statuses
      {:ok, execution1} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      {:ok, execution2} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      {:ok, _execution3} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "pending",
          target_all: false
        })

      {:ok, _execution4} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "completed",
          target_all: false
        })

      conn = get(conn, ~p"/api/agents/command_executions")

      assert %{"command_executions" => executions} = json_response(conn, 200)
      assert length(executions) == 2

      execution_ids = Enum.map(executions, & &1["id"])
      assert execution1.id in execution_ids
      assert execution2.id in execution_ids

      # Verify command_text is included
      first_execution = hd(executions)
      assert first_execution["command_text"] == command.command_text
      assert first_execution["command_id"] == command.id
      assert first_execution["status"] == "sent"
    end

    test "returns empty list when no sent commands", %{auth_conn: conn, node: node} do
      command = command_fixture()

      # Only pending commands
      {:ok, _execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "pending",
          target_all: false
        })

      conn = get(conn, ~p"/api/agents/command_executions")

      assert %{"command_executions" => []} = json_response(conn, 200)
    end

    test "returns 401 without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/agents/command_executions")

      assert json_response(conn, 401)
    end

    test "only returns commands for authenticated node", %{auth_conn: conn, node: node} do
      command = command_fixture()

      # Create execution for this node
      {:ok, my_execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      # Create execution for another node
      other_node = node_fixture(%{api_token: "other-token"})

      {:ok, _other_execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: other_node.id,
          status: "sent",
          target_all: false
        })

      conn = get(conn, ~p"/api/agents/command_executions")

      assert %{"command_executions" => executions} = json_response(conn, 200)
      assert length(executions) == 1
      assert hd(executions)["id"] == my_execution.id
    end

    test "returns executions in insertion order (oldest first)", %{auth_conn: conn, node: node} do
      command = command_fixture()

      # Create multiple executions
      {:ok, execution1} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      Process.sleep(10)

      {:ok, execution2} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      Process.sleep(10)

      {:ok, execution3} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      conn = get(conn, ~p"/api/agents/command_executions")

      assert %{"command_executions" => executions} = json_response(conn, 200)
      execution_ids = Enum.map(executions, & &1["id"])

      # Should be in order: oldest → newest
      assert execution_ids == [execution1.id, execution2.id, execution3.id]
    end
  end

  describe "PATCH /api/agents/command_executions/:id (result reporting)" do
    setup %{auth_conn: conn, node: node} do
      command = command_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      {:ok, conn: conn, node: node, execution: execution}
    end

    test "updates command execution with results", %{auth_conn: conn, execution: execution} do
      update_params = %{
        "status" => "completed",
        "output" => "Command executed successfully",
        "exit_code" => 0
      }

      conn = patch(conn, ~p"/api/agents/command_executions/#{execution.id}", update_params)

      assert %{"data" => updated_execution} = json_response(conn, 200)
      assert updated_execution["id"] == execution.id

      # Verify in database
      updated = Commands.get_command_execution!(execution.id)
      assert updated.status == "completed"
      assert updated.output == "Command executed successfully"
      assert updated.exit_code == 0
      assert updated.completed_at != nil
    end

    test "returns 403 when execution belongs to different node", %{conn: conn, execution: execution} do
      # Create another node
      other_node = node_fixture(%{api_token: "other-token"})

      # Authenticate as other node
      other_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer other-token")

      update_params = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      conn = patch(other_conn, ~p"/api/agents/command_executions/#{execution.id}", update_params)

      assert %{"error" => "Forbidden"} = json_response(conn, 403)
    end

    test "returns 422 when execution is not in 'sent' status", %{auth_conn: conn, node: node} do
      command = command_fixture()

      {:ok, pending_execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "pending",
          target_all: false
        })

      update_params = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      conn = patch(conn, ~p"/api/agents/command_executions/#{pending_execution.id}", update_params)

      assert %{"error" => "Command execution is not in 'sent' status"} =
               json_response(conn, 422)
    end

    test "returns 401 without authentication", %{conn: conn, execution: execution} do
      update_params = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      conn = patch(conn, ~p"/api/agents/command_executions/#{execution.id}", update_params)

      assert json_response(conn, 401)
    end

    test "returns 404 when execution doesn't exist", %{auth_conn: conn} do
      fake_id = Ecto.UUID.generate()

      update_params = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      conn = patch(conn, ~p"/api/agents/command_executions/#{fake_id}", update_params)

      assert json_response(conn, 404)
    end
  end
end
