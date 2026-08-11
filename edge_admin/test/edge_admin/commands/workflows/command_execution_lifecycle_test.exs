# edge_admin/test/edge_admin/commands/workflows/command_execution_lifecycle_test.exs
defmodule EdgeAdmin.Commands.Workflows.CommandExecutionLifecycleTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  defp insert_cluster do
    number = unique_id()

    Repo.insert!(%Cluster{
      id: Ecto.UUID.generate(),
      name: "cluster-#{number}",
      ipv4_range: "100.#{64 + rem(div(number, 256), 64)}.#{rem(number, 256)}.0/24",
      ipv6_range: "fd7a:91c2:4e8b:#{rem(number, 65_536)}::/64"
    })
  end

  defp insert_node(cluster) do
    Repo.insert!(%Node{
      id: Ecto.UUID.generate(),
      cluster_id: cluster.id,
      vpn_host_id: Ecto.UUID.generate(),
      status: :healthy,
      version: "0.1.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9586,
      http_proxy_port: 8080,
      socks5_proxy_port: 1080,
      api_token: Ecto.UUID.generate(),
      proxy_password: Ecto.UUID.generate()
    })
  end

  defp insert_command do
    Repo.insert!(%Command{id: Ecto.UUID.generate(), command_text: "echo hello", targeting: %{}})
  end

  defp insert_execution(command, node, status) do
    Repo.insert!(%CommandExecution{
      id: Ecto.UUID.generate(),
      command_id: command.id,
      node_id: node.id,
      status: status
    })
  end

  describe "drop_node_command_executions/2" do
    test "drops only non-terminal executions and preserves their event snapshots" do
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
end
