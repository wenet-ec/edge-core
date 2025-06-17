# edge_admin/test/edge_admin/commands_test.exs
defmodule EdgeAdmin.CommandsTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Commands

  describe "commands" do
    alias EdgeAdmin.Commands.Command

    import EdgeAdmin.CommandsFixtures

    @invalid_attrs %{commands: nil}

    test "list_commands/0 returns all commands" do
      command = command_fixture()
      assert Commands.list_commands() == [command]
    end

    test "get_command!/1 returns the command with given id" do
      command = command_fixture()
      assert Commands.get_command!(command.id) == command
    end

    test "create_command/1 with valid data creates a command" do
      valid_attrs = %{commands: ["echo 'test'", "pwd"]}

      assert {:ok, %Command{} = command} = Commands.create_command(valid_attrs)
      assert command.commands == ["echo 'test'", "pwd"]
    end

    test "create_command/1 with empty commands array returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{commands: []})
    end

    test "create_command/1 with blank commands returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{commands: ["", "  "]})
    end

    test "create_command/1 with non-string commands returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{commands: [123, "valid"]})
    end

    test "create_command/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(@invalid_attrs)
    end

    test "update_command/2 with valid data updates the command" do
      command = command_fixture()
      update_attrs = %{commands: ["systemctl status nginx"]}

      assert {:ok, %Command{} = command} = Commands.update_command(command, update_attrs)
      assert command.commands == ["systemctl status nginx"]
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

    test "list_command_executions_with_filters/1 filters executions by various criteria" do
      command1 = command_fixture()
      command2 = command_fixture()
      node1 = node_fixture()
      node2 = node_fixture()

      execution1 =
        command_execution_fixture(%{
          command_id: command1.id,
          node_id: node1.id,
          status: "pending"
        })

      command_execution_fixture(%{
        command_id: command1.id,
        node_id: node2.id,
        status: "completed"
      })

      command_execution_fixture(%{command_id: command2.id, node_id: node1.id, status: "pending"})

      # Filter by command_id
      command1_executions = Commands.list_command_executions_with_filters(command_id: command1.id)
      assert length(command1_executions) == 2

      # Filter by node_id
      node1_executions = Commands.list_command_executions_with_filters(node_id: node1.id)
      assert length(node1_executions) == 2

      # Filter by status
      pending_executions = Commands.list_command_executions_with_filters(status: "pending")
      assert length(pending_executions) == 2

      # Multiple filters
      specific_executions =
        Commands.list_command_executions_with_filters(
          command_id: command1.id,
          node_id: node1.id,
          status: "pending"
        )

      assert length(specific_executions) == 1
      assert hd(specific_executions).id == execution1.id

      # Invalid filter is ignored
      all_executions = Commands.list_command_executions_with_filters(invalid_filter: "value")
      assert length(all_executions) == 3
    end
  end
end
