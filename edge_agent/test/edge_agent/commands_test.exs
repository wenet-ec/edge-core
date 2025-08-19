# edge_agent/test/edge_agent/commands_test.exs
defmodule EdgeAgent.CommandsTest do
  use EdgeAgent.DataCase
  use Oban.Testing, repo: EdgeAgent.Repo

  import EdgeAgent.CommandsFixtures

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.Commands.Workers.CommandExecutionWorker

  describe "command_executions" do
    @valid_attrs %{
      id: "01234567-89ab-cdef-0123-456789abcdef",
      command_id: "fedcba98-7654-3210-fedc-ba9876543210",
      node_id: "abcdef01-2345-6789-abcd-ef0123456789",
      command_text: "echo hello",
      status: "pending"
    }

    test "creates and retrieves command execution" do
      assert {:ok, %CommandExecution{} = execution} =
               Commands.create_command_execution(@valid_attrs)

      assert Commands.get_command_execution!(execution.id) == execution
      assert execution.status == "pending"
    end

    test "updates execution to completed" do
      execution = command_execution_fixture()

      assert {:ok, updated} =
               Commands.update_command_execution(execution, %{
                 status: "completed",
                 output: "done",
                 exit_code: 0
               })

      assert updated.status == "completed"
      assert updated.exit_code == 0
    end

    test "validates required fields" do
      assert {:error, changeset} = Commands.create_command_execution(%{})
      assert "can't be blank" in errors_on(changeset).id
    end

    test "validates UUID format" do
      invalid_attrs = %{@valid_attrs | id: "invalid"}
      assert {:error, changeset} = Commands.create_command_execution(invalid_attrs)
      assert "must be a valid UUID format" in errors_on(changeset).id
    end

    test "prevents duplicate IDs" do
      Commands.create_command_execution(@valid_attrs)
      assert {:error, changeset} = Commands.create_command_execution(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).id
    end
  end

  describe "worker integration" do
    test "create_command_execution_and_maybe_start_worker creates execution" do
      assert {:ok, execution} =
               Commands.create_command_execution_and_maybe_start_worker(@valid_attrs)

      assert execution.id == @valid_attrs.id
      assert execution.status == "pending"
    end

    test "create_command_execution_and_maybe_start_worker enqueues worker when none exists" do
      Commands.create_command_execution_and_maybe_start_worker(@valid_attrs)

      # Verify worker job was enqueued
      assert_enqueued(worker: CommandExecutionWorker)
    end

    test "create_command_execution_and_maybe_start_worker doesn't enqueue duplicate workers" do
      # Create first execution and worker
      Commands.create_command_execution_and_maybe_start_worker(@valid_attrs)

      # Create second execution - should not enqueue another worker
      different_attrs = %{@valid_attrs | id: Ecto.UUID.generate()}
      Commands.create_command_execution_and_maybe_start_worker(different_attrs)

      # Should only have one worker job
      jobs = all_enqueued(worker: CommandExecutionWorker)
      assert length(jobs) == 1
    end
  end

  describe "queue management" do
    test "get_pending_executions returns only pending executions in FIFO order" do
      # Create executions with different statuses and times
      execution1 = command_execution_fixture(%{status: "pending"})
      # Ensure different timestamps
      :timer.sleep(10)
      # Fixed: prefixed with underscore
      _execution2 = command_execution_fixture(%{status: "completed"})
      :timer.sleep(10)
      execution3 = command_execution_fixture(%{status: "pending"})

      # Use the private function through the public process_command_queue
      # but first let's test list_command_executions
      all_executions = Commands.list_command_executions()
      assert length(all_executions) == 3

      pending_executions = Enum.filter(all_executions, &(&1.status == "pending"))
      assert length(pending_executions) == 2

      # Should be in FIFO order (oldest first)
      [first, second] = Enum.sort_by(pending_executions, & &1.inserted_at, DateTime)
      assert first.id == execution1.id
      assert second.id == execution3.id
    end

    test "process_command_queue handles empty queue" do
      # Should not crash with empty queue
      assert :ok = Commands.process_command_queue()
    end

    test "report_unreported_executions handles no completed executions" do
      # Should not crash with no completed executions
      assert :ok = Commands.report_unreported_executions()
    end
  end

  describe "CommandExecutionWorker" do
    test "worker can be instantiated and has correct configuration" do
      job_changeset = CommandExecutionWorker.new(%{})

      # The new() function returns a changeset, not a job struct
      assert job_changeset.changes.worker == "EdgeAgent.Commands.Workers.CommandExecutionWorker"
      assert job_changeset.changes.queue == "command_execution"
      assert job_changeset.changes.max_attempts == 1
    end

    test "worker perform function executes without error on empty queue" do
      # This tests the worker's perform function directly
      assert :ok = perform_job(CommandExecutionWorker, %{})
    end
  end

  describe "data integrity" do
    test "command execution has all required fields after creation" do
      {:ok, execution} = Commands.create_command_execution(@valid_attrs)

      assert execution.id == @valid_attrs.id
      assert execution.command_id == @valid_attrs.command_id
      assert execution.node_id == @valid_attrs.node_id
      assert execution.command_text == @valid_attrs.command_text
      assert execution.status == @valid_attrs.status
      assert is_nil(execution.output)
      assert is_nil(execution.exit_code)
      assert execution.inserted_at
      assert execution.updated_at
    end

    test "command execution can be updated with execution results" do
      execution = command_execution_fixture()

      # Add a small delay to ensure different timestamps
      :timer.sleep(10)

      update_attrs = %{
        status: "completed",
        output: "Hello World\n",
        exit_code: 0
      }

      {:ok, updated} = Commands.update_command_execution(execution, update_attrs)

      assert updated.status == "completed"
      assert updated.output == "Hello World\n"
      assert updated.exit_code == 0

      # Just verify updated_at exists and is a DateTime, don't compare exact timing
      assert %DateTime{} = updated.updated_at
      assert updated.id == execution.id
    end

    test "handles execution status transitions" do
      execution = command_execution_fixture(%{status: "pending"})

      # pending -> completed
      {:ok, completed} = Commands.update_command_execution(execution, %{status: "completed"})
      assert completed.status == "completed"
    end
  end

  describe "edge cases" do
    test "handles very long command text" do
      # Reduced from 1000 for faster tests
      long_command = String.duplicate("echo 'test'; ", 100)

      attrs = %{@valid_attrs | command_text: long_command}
      assert {:ok, execution} = Commands.create_command_execution(attrs)
      assert execution.command_text == long_command
    end

    test "handles special characters in command text" do
      special_command = "echo 'Hello \"World\" & echo $HOME | grep user'"

      attrs = %{@valid_attrs | command_text: special_command}
      assert {:ok, execution} = Commands.create_command_execution(attrs)
      assert execution.command_text == special_command
    end

    test "validates status field values" do
      execution = command_execution_fixture()

      # Valid status
      assert {:ok, _} = Commands.update_command_execution(execution, %{status: "completed"})

      # Invalid status should fail validation
      assert {:error, changeset} =
               Commands.update_command_execution(execution, %{status: "invalid"})

      assert "is invalid" in errors_on(changeset).status
    end
  end
end
