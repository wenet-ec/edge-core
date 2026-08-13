# edge_agent/test/edge_agent/commands/commands_test.exs
defmodule EdgeAgent.CommandsTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Repo

  @execution_id "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  @command_id "11111111-2222-3333-4444-555555555555"
  @node_id "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => @execution_id,
        "command_id" => @command_id,
        "node_id" => @node_id,
        "command_text" => "uptime",
        "timeout" => 30_000,
        "expires_at" => ~U[2099-01-01 00:00:00Z],
        "status" => "pending"
      },
      overrides
    )
  end

  describe "create_command_execution_and_enqueue_worker/1" do
    test "creates a local command execution for first delivery" do
      assert {:ok, execution} = Commands.create_command_execution_and_enqueue_worker(valid_attrs())

      assert execution.id == @execution_id
      assert execution.command_id == @command_id
      assert execution.node_id == @node_id
      assert execution.command_text == "uptime"
      assert execution.status == :pending
      assert Repo.aggregate(CommandExecution, :count) == 1
    end

    test "returns the local command execution for duplicate delivery" do
      assert {:ok, first} = Commands.create_command_execution_and_enqueue_worker(valid_attrs())

      assert {:ok, second} = Commands.create_command_execution_and_enqueue_worker(valid_attrs())

      assert second.id == first.id
      assert second.command_id == first.command_id
      assert Repo.aggregate(CommandExecution, :count) == 1
    end
  end
end
