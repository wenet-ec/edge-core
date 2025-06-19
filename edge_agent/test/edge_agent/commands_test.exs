# edge_agent/test/edge_agent/commands_test.exs
defmodule EdgeAgent.CommandsTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.CommandExecution

  import EdgeAgent.CommandsFixtures

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
end
