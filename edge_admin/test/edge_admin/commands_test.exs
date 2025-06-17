# edge_admin/test/edge_admin/commands_test.exs
defmodule EdgeAdmin.CommandsTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Commands

  describe "commands" do
    alias EdgeAdmin.Commands.Command

    import EdgeAdmin.CommandsFixtures

    @invalid_attrs %{command_text: nil}

    test "list_commands/0 returns all commands" do
      command = command_fixture()
      assert Commands.list_commands() == [command]
    end

    test "get_command!/1 returns the command with given id" do
      command = command_fixture()
      assert Commands.get_command!(command.id) == command
    end

    test "create_command/1 with valid data creates a command" do
      valid_attrs = %{command_text: "echo 'test'\npwd"}

      assert {:ok, %Command{} = command} = Commands.create_command(valid_attrs)
      assert command.command_text == "echo 'test'\npwd"
    end

    test "create_command/1 with single line command creates a command" do
      valid_attrs = %{command_text: "echo 'hello world'"}

      assert {:ok, %Command{} = command} = Commands.create_command(valid_attrs)
      assert command.command_text == "echo 'hello world'"
    end

    test "create_command/1 with empty command_text returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{command_text: ""})
    end

    test "create_command/1 with whitespace only command_text returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{command_text: "   \n\t  "})
    end

    test "create_command/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(@invalid_attrs)
    end

    test "update_command/2 with valid data updates the command" do
      command = command_fixture()
      update_attrs = %{command_text: "systemctl status nginx"}

      assert {:ok, %Command{} = command} = Commands.update_command(command, update_attrs)
      assert command.command_text == "systemctl status nginx"
    end

    test "update_command/2 with invalid data returns error changeset" do
      command = command_fixture()
      assert {:error, %Ecto.Changeset{}} = Commands.update_command(command, @invalid_attrs)
      assert command == Commands.get_command!(command.id)
    end

    test "delete_command/1 deletes the command" do
      command = command_fixture()
      assert {:ok, %Command{}} = Commands.delete_command(command)
      assert_raise Ecto.NoResultsError, fn -> Commands.get_command!(command.id) end
    end

    test "change_command/1 returns a command changeset" do
      command = command_fixture()
      assert %Ecto.Changeset{} = Commands.change_command(command)
    end
  end

  describe "command_executions" do
    alias EdgeAdmin.Commands.CommandExecution

    import EdgeAdmin.CommandsFixtures
    import EdgeAdmin.NodesFixtures

    @invalid_attrs %{status: nil}

    test "list_command_executions/0 returns all command_executions" do
      command_execution = command_execution_fixture()
      assert Commands.list_command_executions() == [command_execution]
    end

    test "get_command_execution!/1 returns the command_execution with given id" do
      command_execution = command_execution_fixture()
      assert Commands.get_command_execution!(command_execution.id) == command_execution
    end

    test "create_command_execution/1 with valid data creates a command_execution" do
      command = command_fixture()
      node = node_fixture()

      valid_attrs = %{
        command_id: command.id,
        node_id: node.id,
        status: "pending",
        target_all: false
      }

      assert {:ok, %CommandExecution{} = execution} =
               Commands.create_command_execution(valid_attrs)

      assert execution.status == "pending"
      assert execution.target_all == false
      assert execution.command_id == command.id
      assert execution.node_id == node.id
    end

    test "create_command_execution/1 with target_all=true creates without node_id" do
      command = command_fixture()

      valid_attrs = %{
        command_id: command.id,
        node_id: nil,
        status: "pending",
        target_all: true
      }

      assert {:ok, %CommandExecution{} = execution} =
               Commands.create_command_execution(valid_attrs)

      assert execution.status == "pending"
      assert execution.target_all == true
      assert execution.command_id == command.id
      assert execution.node_id == nil
    end

    test "create_command_execution/1 with target_all=false requires node_id" do
      command = command_fixture()

      invalid_attrs = %{
        command_id: command.id,
        node_id: nil,
        status: "pending",
        target_all: false
      }

      assert {:error, %Ecto.Changeset{}} = Commands.create_command_execution(invalid_attrs)
    end

    test "create_command_execution/1 with invalid status returns error changeset" do
      command = command_fixture()
      node = node_fixture()

      invalid_attrs = %{
        command_id: command.id,
        node_id: node.id,
        status: "invalid_status"
      }

      assert {:error, %Ecto.Changeset{}} = Commands.create_command_execution(invalid_attrs)
    end

    test "create_command_execution/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command_execution(@invalid_attrs)
    end

    test "update_command_execution/2 with completion data updates the execution" do
      command_execution = command_execution_fixture()

      update_attrs = %{
        status: "completed",
        output: "Command executed successfully",
        exit_code: 0,
        completed_at: ~U[2025-06-17 02:07:00Z]
      }

      assert {:ok, %CommandExecution{} = execution} =
               Commands.update_command_execution(command_execution, update_attrs)

      assert execution.status == "completed"
      assert execution.output == "Command executed successfully"
      assert execution.exit_code == 0
      assert execution.completed_at == ~U[2025-06-17 02:07:00Z]
    end

    test "update_command_execution/2 with invalid data returns error changeset" do
      command_execution = command_execution_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Commands.update_command_execution(command_execution, @invalid_attrs)

      assert command_execution == Commands.get_command_execution!(command_execution.id)
    end

    test "delete_command_execution/1 deletes the command_execution" do
      command_execution = command_execution_fixture()
      assert {:ok, %CommandExecution{}} = Commands.delete_command_execution(command_execution)

      assert_raise Ecto.NoResultsError, fn ->
        Commands.get_command_execution!(command_execution.id)
      end
    end

    test "change_command_execution/1 returns a command_execution changeset" do
      command_execution = command_execution_fixture()
      assert %Ecto.Changeset{} = Commands.change_command_execution(command_execution)
    end
  end

  describe "query helpers" do
    import EdgeAdmin.CommandsFixtures
    import EdgeAdmin.NodesFixtures

    test "valid_statuses/0 returns valid status list" do
      assert Commands.valid_statuses() == ["pending", "sent", "completed"]
    end

    test "list_command_executions_by_status/1 filters by status" do
      _pending = command_execution_fixture(%{status: "pending"})
      completed = completed_command_execution_fixture()

      pending_executions = Commands.list_command_executions_by_status("pending")
      completed_executions = Commands.list_command_executions_by_status("completed")

      assert length(pending_executions) == 1
      assert length(completed_executions) == 1
      assert hd(completed_executions).id == completed.id
    end

    test "list_pending_executions_for_node/1 returns pending executions for specific node" do
      node1 = node_fixture()
      node2 = node_fixture()

      command_execution_fixture(%{node_id: node1.id, status: "pending"})
      command_execution_fixture(%{node_id: node1.id, status: "completed"})
      command_execution_fixture(%{node_id: node2.id, status: "pending"})

      pending_for_node1 = Commands.list_pending_executions_for_node(node1.id)

      assert length(pending_for_node1) == 1
      assert hd(pending_for_node1).node_id == node1.id
      assert hd(pending_for_node1).status == "pending"
    end

    test "count_pending_executions_for_node/1 returns count of pending executions" do
      node = node_fixture()

      assert Commands.count_pending_executions_for_node(node.id) == 0

      command_execution_fixture(%{node_id: node.id, status: "pending"})
      command_execution_fixture(%{node_id: node.id, status: "pending"})
      command_execution_fixture(%{node_id: node.id, status: "completed"})

      assert Commands.count_pending_executions_for_node(node.id) == 2
    end

    test "has_pending_executions?/1 returns boolean for pending executions" do
      node = node_fixture()

      assert Commands.has_pending_executions?(node.id) == false

      _execution = command_execution_fixture(%{node_id: node.id, status: "pending"})

      assert Commands.has_pending_executions?(node.id) == true
    end

    test "list_pending_executions_by_node/0 returns all pending executions ordered by node and time" do
      node1 = node_fixture()
      node2 = node_fixture()

      # Create executions with specific timing
      command_execution_fixture(%{node_id: node1.id, status: "pending"})
      command_execution_fixture(%{node_id: node2.id, status: "pending"})
      command_execution_fixture(%{node_id: node1.id, status: "pending"})
      command_execution_fixture(%{node_id: node1.id, status: "completed"})

      pending_executions = Commands.list_pending_executions_by_node()

      assert length(pending_executions) == 3

      # The exact order depends on node UUIDs, but we can verify grouping
      node1_executions = Enum.filter(pending_executions, &(&1.node_id == node1.id))
      node2_executions = Enum.filter(pending_executions, &(&1.node_id == node2.id))

      assert length(node1_executions) == 2
      assert length(node2_executions) == 1
    end

    test "get_oldest_pending_execution_for_node/1 returns oldest pending execution" do
      node = node_fixture()

      assert Commands.get_oldest_pending_execution_for_node(node.id) == nil

      execution1 = command_execution_fixture(%{node_id: node.id, status: "pending"})
      command_execution_fixture(%{node_id: node.id, status: "pending"})

      oldest = Commands.get_oldest_pending_execution_for_node(node.id)

      # First created should be oldest
      assert oldest.id == execution1.id
    end
  end

  describe "filtering and pagination" do
    import EdgeAdmin.CommandsFixtures
    import EdgeAdmin.NodesFixtures

    setup do
      # Create test data for filtering
      command1 = command_fixture()
      command2 = command_fixture()
      node1 = node_fixture()
      node2 = node_fixture()

      _execution1 =
        command_execution_fixture(%{
          command_id: command1.id,
          node_id: node1.id,
          status: "pending",
          output: "Starting process..."
        })

      _execution2 =
        command_execution_fixture(%{
          command_id: command1.id,
          node_id: node2.id,
          status: "completed",
          exit_code: 0,
          output: "Process completed successfully"
        })

      _execution3 =
        command_execution_fixture(%{
          command_id: command2.id,
          node_id: node1.id,
          status: "completed",
          exit_code: 1,
          output: "Process failed with error"
        })

      {:ok, command1: command1, command2: command2, node1: node1, node2: node2}
    end

    test "apply_filtering_pagination/1 returns paginated results with default settings" do
      result = Commands.apply_filtering_pagination(%{})

      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 3
      assert result.page == 1
      assert result.page_size == 20
      assert result.total == 3
    end

    test "list_command_executions_with_filtering_pagination/1 works with basic pagination" do
      result = Commands.list_command_executions_with_filtering_pagination(%{"page_size" => "2"})

      assert length(result.data) == 2
      assert result.page_size == 2
      assert result.total_pages == 2
    end

    test "filtering by status works", %{} do
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"status" => "completed"})

      assert length(result.data) == 2
      assert result.filters == %{"status" => "completed"}
      Enum.each(result.data, fn execution -> assert execution.status == "completed" end)
    end

    test "filtering by command_id works", %{command1: command1} do
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"command_id" => command1.id})

      assert length(result.data) == 2
      assert result.filters == %{"command_id" => command1.id}
      Enum.each(result.data, fn execution -> assert execution.command_id == command1.id end)
    end

    test "filtering by exit_code works" do
      result = Commands.list_command_executions_with_filtering_pagination(%{"exit_code" => "0"})

      assert length(result.data) == 1
      assert result.filters == %{"exit_code" => "0"}
      assert hd(result.data).exit_code == 0
    end

    test "filtering by output with wildcards works" do
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"output" => "*error*"})

      assert length(result.data) == 1
      assert result.filters == %{"output" => "*error*"}
      assert String.contains?(hd(result.data).output, "error")
    end

    test "sorting works" do
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"sort" => "status:asc"})

      statuses = Enum.map(result.data, & &1.status)
      # Should be: completed, completed, pending (alphabetical)
      assert statuses == ["completed", "completed", "pending"]
    end

    test "multiple filters work together", %{command1: command1} do
      result =
        Commands.list_command_executions_with_filtering_pagination(%{
          "command_id" => command1.id,
          "status" => "completed"
        })

      assert length(result.data) == 1
      assert result.filters == %{"command_id" => command1.id, "status" => "completed"}
      execution = hd(result.data)
      assert execution.command_id == command1.id
      assert execution.status == "completed"
    end
  end
end
