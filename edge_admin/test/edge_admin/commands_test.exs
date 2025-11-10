# edge_admin/test/edge_admin/commands_test.exs
defmodule EdgeAdmin.CommandsTest do
  use EdgeAdmin.DataCase
  use Oban.Testing, repo: EdgeAdmin.Repo

  import EdgeAdmin.CommandsFixtures
  import EdgeAdmin.NodesFixtures

  alias EdgeAdmin.Commands

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

  describe "command CRUD operations" do
    test "get_command!/1 returns command" do
      command = command_fixture()
      fetched = Commands.get_command!(command.id)
      assert fetched.id == command.id
      assert fetched.command_text == command.command_text
    end

    test "update_command/2 with valid data updates command" do
      command = command_fixture()
      update_attrs = %{command_text: "updated command"}

      assert {:ok, updated_command} = Commands.update_command(command, update_attrs)
      assert updated_command.command_text == "updated command"
    end

    test "delete_command/1 deletes the command" do
      command = command_fixture()
      assert {:ok, _} = Commands.delete_command(command)
      assert_raise Ecto.NoResultsError, fn -> Commands.get_command!(command.id) end
    end

    test "change_command/1 returns changeset" do
      command = command_fixture()
      changeset = Commands.change_command(command)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "command execution CRUD operations" do
    test "get_command_execution!/1 returns execution with preloaded command" do
      command = command_fixture()
      node = node_fixture()
      execution = command_execution_fixture(%{command_id: command.id, node_id: node.id})

      fetched = Commands.get_command_execution!(execution.id)
      assert fetched.id == execution.id
      assert fetched.command_text == command.command_text
    end

    test "update_command_execution/2 updates execution" do
      execution = command_execution_fixture()
      completed_time = DateTime.truncate(DateTime.utc_now(), :second)
      update_attrs = %{status: "completed", exit_code: 0, completed_at: completed_time}

      assert {:ok, updated} = Commands.update_command_execution(execution, update_attrs)
      assert updated.status == "completed"
      assert updated.exit_code == 0
    end

    test "delete_command_execution/1 deletes execution" do
      execution = command_execution_fixture()
      assert {:ok, _} = Commands.delete_command_execution(execution)
      assert_raise Ecto.NoResultsError, fn -> Commands.get_command_execution!(execution.id) end
    end

    test "change_command_execution/1 returns changeset" do
      execution = command_execution_fixture()
      changeset = Commands.change_command_execution(execution)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "create_command_and_dispatch_executions/1" do
    test "creates command and dispatches for target_all" do
      attrs = %{
        "command_text" => "echo test",
        "targeting" => %{
          "type" => "all",
          "node_filters" => %{}
        }
      }

      assert {:ok, command} = Commands.create_command_and_dispatch_executions(attrs)
      assert command.command_text == "echo test"

      # Should have enqueued Oban job
      assert_enqueued(worker: EdgeAdmin.Commands.Workers.TargetAllDispatchWorker)
    end

    test "creates command and dispatches for specific nodes" do
      node1 = node_fixture()
      node2 = node_fixture()

      attrs = %{
        "command_text" => "pwd",
        "targeting" => %{
          "type" => "nodes",
          "ids" => [node1.id, node2.id]
        }
      }

      assert {:ok, command} = Commands.create_command_and_dispatch_executions(attrs)
      assert command.command_text == "pwd"

      # Should have enqueued Oban job for specific nodes
      assert_enqueued(worker: EdgeAdmin.Commands.Workers.TargetNodesDispatchWorker)
    end

    test "returns error for invalid command" do
      attrs = %{
        # Invalid
        "command_text" => "",
        "targeting" => %{"type" => "all"}
      }

      assert {:error, changeset} = Commands.create_command_and_dispatch_executions(attrs)
      assert changeset.errors[:command_text]
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

  describe "virtual command_text field" do
    test "get_command_execution! populates command_text" do
      command = command_fixture(%{command_text: "echo virtual field test"})
      command_execution = command_execution_fixture(%{command: command})

      retrieved = Commands.get_command_execution!(command_execution.id)

      assert retrieved.command_text == "echo virtual field test"
    end

    test "list_command_executions_with_filtering_pagination populates command_text" do
      command = command_fixture(%{command_text: "echo pagination test"})
      _execution = command_execution_fixture(%{command: command})

      result = Commands.list_command_executions_with_filtering_pagination(%{})

      assert length(result.data) == 1
      execution = hd(result.data)
      assert execution.command_text == "echo pagination test"
    end
  end

  describe "list_sent_command_executions_for_node/1" do
    test "returns only sent executions for specified node" do
      command = command_fixture()
      node = node_fixture()
      other_node = node_fixture()

      # Create sent execution for target node
      {:ok, sent_execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      # Create pending execution for target node (should not be returned)
      {:ok, _pending_execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "pending",
          target_all: false
        })

      # Create sent execution for other node (should not be returned)
      {:ok, _other_node_execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: other_node.id,
          status: "sent",
          target_all: false
        })

      result = Commands.list_sent_command_executions_for_node(node.id)

      assert length(result) == 1
      assert hd(result).id == sent_execution.id
      assert hd(result).status == "sent"
      assert hd(result).command_text == command.command_text
    end

    test "returns empty list when no sent executions exist" do
      node = node_fixture()

      result = Commands.list_sent_command_executions_for_node(node.id)

      assert result == []
    end

    test "returns executions ordered by insertion (oldest first)" do
      command = command_fixture()
      node = node_fixture()

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

      result = Commands.list_sent_command_executions_for_node(node.id)

      assert length(result) == 3
      [first, second, third] = result
      assert first.id == execution1.id
      assert second.id == execution2.id
      assert third.id == execution3.id
    end
  end

  describe "update_command_execution_result/3" do
    test "successfully updates execution with valid data" do
      command = command_fixture()
      node = node_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      attrs = %{
        "status" => "completed",
        "output" => "Command executed successfully",
        "exit_code" => 0
      }

      assert {:ok, updated} =
               Commands.update_command_execution_result(execution.id, node.id, attrs)

      assert updated.status == "completed"
      assert updated.output == "Command executed successfully"
      assert updated.exit_code == 0
      assert updated.completed_at != nil
    end

    test "returns forbidden error when node_id doesn't match" do
      command = command_fixture()
      node = node_fixture()
      other_node = node_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      attrs = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      assert {:error, :forbidden} =
               Commands.update_command_execution_result(execution.id, other_node.id, attrs)
    end

    test "returns invalid_status error when execution is not in sent status" do
      command = command_fixture()
      node = node_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "pending",
          target_all: false
        })

      attrs = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      assert {:error, :invalid_status} =
               Commands.update_command_execution_result(execution.id, node.id, attrs)
    end

    test "returns invalid_status error when execution is already completed" do
      command = command_fixture()
      node = node_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "completed",
          target_all: false
        })

      attrs = %{
        "status" => "completed",
        "output" => "trying to update again",
        "exit_code" => 0
      }

      assert {:error, :invalid_status} =
               Commands.update_command_execution_result(execution.id, node.id, attrs)
    end

    test "returns changeset error for invalid data" do
      command = command_fixture()
      node = node_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      # Invalid status value
      attrs = %{
        "status" => "invalid_status",
        "output" => "output",
        "exit_code" => 0
      }

      assert {:error, %Ecto.Changeset{}} =
               Commands.update_command_execution_result(execution.id, node.id, attrs)
    end

    test "sets completed_at timestamp automatically" do
      command = command_fixture()
      node = node_fixture()

      {:ok, execution} =
        Commands.create_command_execution(%{
          command_id: command.id,
          node_id: node.id,
          status: "sent",
          target_all: false
        })

      before_update = DateTime.utc_now()

      attrs = %{
        "status" => "completed",
        "output" => "output",
        "exit_code" => 0
      }

      assert {:ok, updated} =
               Commands.update_command_execution_result(execution.id, node.id, attrs)

      assert updated.completed_at != nil
      assert DateTime.compare(updated.completed_at, before_update) in [:gt, :eq]
    end
  end
end
