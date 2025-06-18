# edge_agent/test/edge_agent/commands_test.exs
defmodule EdgeAgent.CommandsTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Commands

  describe "command_executions" do
    alias EdgeAgent.Commands.CommandExecution

    import EdgeAgent.CommandsFixtures

    @invalid_attrs %{
      output: nil,
      status: nil,
      exit_code: nil,
      command_id: nil,
      node_id: nil,
      command_text: nil
    }

    test "list_command_executions/0 returns all command_executions" do
      command_execution = command_execution_fixture()
      assert Commands.list_command_executions() == [command_execution]
    end

    test "get_command_execution!/1 returns the command_execution with given id" do
      command_execution = command_execution_fixture()
      assert Commands.get_command_execution!(command_execution.id) == command_execution
    end

    test "create_command_execution/1 with valid data creates a command_execution" do
      valid_attrs = %{
        command_id: "7488a646-e31f-11e4-aace-600308960662",
        node_id: "7488a646-e31f-11e4-aace-600308960662",
        command_text: "echo hello",
        status: "pending",
        output: "some output",
        exit_code: 0
      }

      assert {:ok, %CommandExecution{} = command_execution} =
               Commands.create_command_execution(valid_attrs)

      assert command_execution.output == "some output"
      assert command_execution.status == "pending"
      assert command_execution.exit_code == 0
      assert command_execution.command_id == "7488a646-e31f-11e4-aace-600308960662"
      assert command_execution.node_id == "7488a646-e31f-11e4-aace-600308960662"
      assert command_execution.command_text == "echo hello"
    end

    test "create_command_execution/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Commands.create_command_execution(@invalid_attrs)
    end

    test "update_command_execution/2 with valid data updates the command_execution" do
      command_execution = command_execution_fixture()

      update_attrs = %{
        output: "command completed",
        status: "completed",
        exit_code: 0
      }

      assert {:ok, %CommandExecution{} = command_execution} =
               Commands.update_command_execution(command_execution, update_attrs)

      assert command_execution.output == "command completed"
      assert command_execution.status == "completed"
      assert command_execution.exit_code == 0
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
end
