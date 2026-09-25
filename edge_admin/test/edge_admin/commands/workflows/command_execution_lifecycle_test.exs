# edge_admin/test/edge_admin/commands/workflows/command_execution_lifecycle_test.exs
defmodule EdgeAdmin.Commands.Workflows.CommandExecutionLifecycleTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster, do: Fixtures.insert_cluster!()
  defp insert_node(cluster), do: Fixtures.insert_node!(cluster.id)

  defp insert_command, do: Fixtures.insert_command!()

  defp insert_execution(command, node, status) do
    Fixtures.insert_command_execution!(%{command_id: command.id, node_id: node.id, status: status})
  end

  describe "drop_node_command_executions/2" do
    test "drops only pending and sent executions and preserves their event snapshots" do
      cluster = insert_cluster()
      node = insert_node(cluster)
      pending_command = insert_command()
      sent_command = insert_command()
      completed_command = insert_command()
      pending = insert_execution(pending_command, node, :pending)
      sent = insert_execution(sent_command, node, :sent)
      completed = insert_execution(completed_command, node, :completed)

      dropped = CommandExecutionLifecycle.drop_node_command_executions(node.id, cluster.name)

      assert MapSet.new(Enum.map(dropped, & &1.execution.id)) == MapSet.new([pending.id, sent.id])
      assert Enum.all?(dropped, &(&1.execution.status == :dropped))
      assert Enum.all?(dropped, &(&1.execution.node_id == node.id))

      assert MapSet.new(Enum.map(dropped, & &1.command.id)) ==
               MapSet.new([pending_command.id, sent_command.id])

      assert Enum.all?(dropped, &(&1.cluster_name == cluster.name))

      assert Repo.get!(CommandExecution, pending.id).status == :dropped
      assert Repo.get!(CommandExecution, sent.id).status == :dropped
      assert Repo.get!(CommandExecution, completed.id).status == :completed
    end
  end

  describe "update_command_execution_result/2" do
    test "accepts an Agent result while Admin still has the execution pending" do
      cluster = insert_cluster()
      node = insert_node(cluster)
      command = insert_command()
      execution = insert_execution(command, node, :pending)

      assert {:ok, updated} =
               CommandExecutionLifecycle.update_command_execution_result(execution, %{
                 "status" => "completed",
                 "output" => "hello\n",
                 "exit_code" => 0,
                 "completed_at" => "2010-01-01T00:00:00Z"
               })

      assert updated.status == :completed
      assert updated.output == "hello\n"
      assert updated.exit_code == 0
      assert %DateTime{} = updated.completed_at
      assert updated.completed_at.microsecond == {0, 0}
      assert updated.sent_at == nil

      persisted = Repo.get!(CommandExecution, execution.id)
      assert persisted.status == :completed
      assert persisted.sent_at == nil
    end
  end
end
