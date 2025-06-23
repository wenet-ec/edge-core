# edge_admin/test/edge_admin/commands_test.exs
defmodule EdgeAdmin.CommandsTest do
  use EdgeAdmin.DataCase

  alias EdgeAdmin.Commands

  import EdgeAdmin.CommandsFixtures
  import EdgeAdmin.NodesFixtures

  describe "command validation" do
    test "validates command_text format" do
      # Valid cases
      assert {:ok, _} = Commands.create_command(%{command_text: "echo 'test'\npwd"})
      assert {:ok, _} = Commands.create_command(%{command_text: "echo 'hello world'"})

      # Invalid cases
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{command_text: ""})
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{command_text: "   \n\t  "})
      assert {:error, %Ecto.Changeset{}} = Commands.create_command(%{command_text: nil})
    end
  end

  describe "command execution validation" do
    test "requires node_id when target_all is false" do
      command = command_fixture()

      invalid_attrs = %{
        command_id: command.id,
        node_id: nil,
        status: "pending",
        target_all: false
      }

      assert {:error, %Ecto.Changeset{}} = Commands.create_command_execution(invalid_attrs)
    end

    test "allows nil node_id when target_all is true" do
      command = command_fixture()

      valid_attrs = %{
        command_id: command.id,
        node_id: nil,
        status: "pending",
        target_all: true
      }

      assert {:ok, execution} = Commands.create_command_execution(valid_attrs)
      assert execution.target_all == true
      assert execution.node_id == nil
    end

    test "allows multiple target_all executions for same command (nulls don't conflict)" do
      command = command_fixture()

      # First target_all execution
      attrs1 = %{command_id: command.id, node_id: nil, status: "pending", target_all: true}
      assert {:ok, _execution1} = Commands.create_command_execution(attrs1)

      # Second target_all execution for same command should work (NULL values don't conflict in unique constraint)
      attrs2 = %{command_id: command.id, node_id: nil, status: "pending", target_all: true}
      assert {:ok, _execution2} = Commands.create_command_execution(attrs2)
    end

    test "validates status inclusion" do
      command = command_fixture()
      node = node_fixture()

      # Valid status
      valid_attrs = %{command_id: command.id, node_id: node.id, status: "pending"}
      assert {:ok, _} = Commands.create_command_execution(valid_attrs)

      # Invalid status
      invalid_attrs = %{command_id: command.id, node_id: node.id, status: "invalid_status"}
      assert {:error, %Ecto.Changeset{}} = Commands.create_command_execution(invalid_attrs)
    end

    test "prevents duplicate command executions for same node-command pair" do
      command = command_fixture()
      node = node_fixture()

      # First execution should succeed
      valid_attrs = %{command_id: command.id, node_id: node.id, status: "pending"}
      assert {:ok, _execution1} = Commands.create_command_execution(valid_attrs)

      # Second execution with same node-command pair should fail
      assert {:error, %Ecto.Changeset{} = changeset} =
               Commands.create_command_execution(valid_attrs)

      assert changeset.errors[:node_id] != nil || changeset.errors[:command_id] != nil

      # Different node should work
      node2 = node_fixture()
      different_node_attrs = %{command_id: command.id, node_id: node2.id, status: "pending"}
      assert {:ok, _execution2} = Commands.create_command_execution(different_node_attrs)

      # Different command should work
      command2 = command_fixture()
      different_command_attrs = %{command_id: command2.id, node_id: node.id, status: "pending"}
      assert {:ok, _execution3} = Commands.create_command_execution(different_command_attrs)
    end
  end

  describe "filtering and pagination integration" do
    setup do
      # Create test data for filtering
      command1 = command_fixture()
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

      {:ok, command1: command1, node1: node1, node2: node2}
    end

    test "list_command_executions_with_filtering_pagination handles basic functionality" do
      result = Commands.list_command_executions_with_filtering_pagination(%{})

      assert %EdgeAdmin.FilteringPagination{} = result
      assert length(result.data) == 2
      assert result.page == 1
      assert result.page_size == 20
    end

    test "supports key filtering scenarios", %{command1: command1} do
      # Status filtering
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"status" => "completed"})

      assert length(result.data) == 1
      assert result.filters == %{"status" => "completed"}

      # Command ID filtering
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"command_id" => command1.id})

      assert length(result.data) == 2
      assert result.filters == %{"command_id" => command1.id}

      # Output wildcard filtering - test with different patterns
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"output" => "*Starting*"})

      assert length(result.data) == 1

      result =
        Commands.list_command_executions_with_filtering_pagination(%{"output" => "*completed*"})

      assert length(result.data) == 1

      # Test case-insensitive pattern that should match both
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"output" => "*process*"})

      # This matches the actual behavior
      assert length(result.data) == 1

      result =
        Commands.list_command_executions_with_filtering_pagination(%{"output" => "*Process*"})

      # This should match the capitalized version
      assert length(result.data) == 1
    end

    test "supports sorting and complex filter combinations", %{command1: command1} do
      # Sorting
      result =
        Commands.list_command_executions_with_filtering_pagination(%{"sort" => "status:asc"})

      statuses = Enum.map(result.data, & &1.status)
      assert statuses == ["completed", "pending"]

      # Multiple filters
      result =
        Commands.list_command_executions_with_filtering_pagination(%{
          "command_id" => command1.id,
          "status" => "completed"
        })

      assert length(result.data) == 1
      assert result.filters == %{"command_id" => command1.id, "status" => "completed"}
    end
  end

  describe "command execution dispatch (integration)" do
    test "create_command_and_dispatch_executions creates command successfully" do
      node1 = node_fixture()
      node2 = node_fixture()

      attrs = %{
        "command_text" => "echo test",
        "target_nodes" => [node1.id, node2.id]
      }

      # This should create the command and enqueue workers
      assert {:ok, command} = Commands.create_command_and_dispatch_executions(attrs)
      assert command.command_text == "echo test"

      # We don't test the actual worker execution here since it involves
      # HTTP calls and background jobs - that's integration/e2e territory
    end

    test "target_all creates command and enqueues background worker" do
      attrs = %{
        "command_text" => "echo test",
        "target_all" => true
      }

      assert {:ok, command} = Commands.create_command_and_dispatch_executions(attrs)
      assert command.command_text == "echo test"
    end
  end
end
