# edge_admin/test/edge_admin/commands/checks/non_finalized_command_executions_check_test.exs
defmodule EdgeAdmin.Commands.Checks.NonFinalizedCommandExecutionsCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Commands.Checks.NonFinalizedCommandExecutionsCheck
  alias EdgeAdmin.Test.Fixtures

  @admin_completed_at ~U[2026-09-25 00:00:00Z]
  # helpers

  defp insert_cluster, do: Fixtures.insert_cluster!()
  defp insert_node(cluster_id), do: Fixtures.insert_node!(cluster_id)

  defp insert_command, do: Fixtures.insert_command!()

  defp insert_execution(command_id, node_id, status, attrs \\ %{}) do
    Fixtures.insert_command_execution!(Map.merge(%{command_id: command_id, node_id: node_id, status: status}, attrs))
  end

  # check/1 — no non-finalized executions

  describe "check/1 — all executions finalized" do
    test "command with no executions returns :ok" do
      command = insert_command()
      assert :ok = NonFinalizedCommandExecutionsCheck.check(command)
    end

    test "command with only completed executions returns :ok" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :completed)
      insert_execution(command.id, node2.id, :completed)
      assert :ok = NonFinalizedCommandExecutionsCheck.check(command)
    end

    test "cancelled and expired executions without an Admin result timestamp are not finalized" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :cancelled)
      insert_execution(command.id, node2.id, :expired)
      assert {:error, {:conflict, reason}} = NonFinalizedCommandExecutionsCheck.check(command)
      assert reason =~ "2"
    end

    test "cancelled and expired executions with an Admin result timestamp are finalized" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :cancelled, %{completed_at: @admin_completed_at})
      insert_execution(command.id, node2.id, :expired, %{completed_at: @admin_completed_at})
      assert :ok = NonFinalizedCommandExecutionsCheck.check(command)
    end
  end

  # check/1 — executions that can still change

  describe "check/1 — non-finalized executions" do
    test "command with pending execution returns conflict error" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node.id, :pending)
      assert {:error, {:conflict, reason}} = NonFinalizedCommandExecutionsCheck.check(command)
      assert reason =~ "1"
    end

    test "command with sent execution returns conflict error" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node.id, :sent)
      assert {:error, {:conflict, reason}} = NonFinalizedCommandExecutionsCheck.check(command)
      assert reason =~ "1"
    end

    test "error count reflects every non-finalized execution" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      node3 = insert_node(cluster.id)
      node4 = insert_node(cluster.id)
      node5 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :pending)
      insert_execution(command.id, node2.id, :sent)
      insert_execution(command.id, node3.id, :completed)
      insert_execution(command.id, node4.id, :cancelled)
      insert_execution(command.id, node5.id, :expired)
      {:error, {:conflict, reason}} = NonFinalizedCommandExecutionsCheck.check(command)
      assert reason =~ "4"
    end
  end
end
