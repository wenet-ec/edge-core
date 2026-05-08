# edge_admin/test/edge_admin/commands/checks/pending_executions_check_test.exs
defmodule EdgeAdmin.Commands.Checks.PendingExecutionsCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Commands.Checks.PendingExecutionsCheck
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  # See cluster_filters_test for rationale: monotonic ints, not random, so
  # birthday-paradox collisions on the small `100.64.X.0/24` space disappear.
  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  defp unique_ipv4_range do
    n = unique_id()
    octet2 = 64 + rem(div(n, 256), 64)
    octet3 = rem(n, 256)
    "100.#{octet2}.#{octet3}.0/24"
  end

  defp insert_cluster do
    Repo.insert!(
      struct(Cluster, %{
        id: Ecto.UUID.generate(),
        name: "cluster-#{unique_id()}",
        ipv4_range: unique_ipv4_range()
      })
    )
  end

  defp insert_node(cluster_id) do
    Repo.insert!(
      struct(Node, %{
        id: Ecto.UUID.generate(),
        cluster_id: cluster_id,
        id_type: "persistent",
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
    )
  end

  defp insert_command do
    Repo.insert!(
      struct(Command, %{
        id: Ecto.UUID.generate(),
        command_text: "echo hello",
        targeting: %{}
      })
    )
  end

  defp insert_execution(command_id, node_id, status) do
    Repo.insert!(
      struct(CommandExecution, %{
        id: Ecto.UUID.generate(),
        command_id: command_id,
        node_id: node_id,
        status: status
      })
    )
  end

  # ---------------------------------------------------------------------------
  # check/1 — no pending executions
  # ---------------------------------------------------------------------------

  describe "check/1 — all executions completed" do
    test "command with no executions returns :ok" do
      command = insert_command()
      assert :ok = PendingExecutionsCheck.check(command)
    end

    test "command with only completed executions returns :ok" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :completed)
      insert_execution(command.id, node2.id, :completed)
      assert :ok = PendingExecutionsCheck.check(command)
    end

    test "command with cancelled and expired executions returns :ok" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :cancelled)
      insert_execution(command.id, node2.id, :expired)
      assert :ok = PendingExecutionsCheck.check(command)
    end
  end

  # ---------------------------------------------------------------------------
  # check/1 — pending or in-flight executions
  # ---------------------------------------------------------------------------

  describe "check/1 — pending or sent executions" do
    test "command with pending execution returns conflict error" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node.id, :pending)
      assert {:error, {:conflict, reason}} = PendingExecutionsCheck.check(command)
      assert reason =~ "1"
    end

    test "command with sent execution returns conflict error" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node.id, :sent)
      assert {:error, {:conflict, reason}} = PendingExecutionsCheck.check(command)
      assert reason =~ "1"
    end

    test "error count reflects all non-completed executions" do
      cluster = insert_cluster()
      node1 = insert_node(cluster.id)
      node2 = insert_node(cluster.id)
      node3 = insert_node(cluster.id)
      command = insert_command()
      insert_execution(command.id, node1.id, :pending)
      insert_execution(command.id, node2.id, :sent)
      insert_execution(command.id, node3.id, :completed)
      {:error, {:conflict, reason}} = PendingExecutionsCheck.check(command)
      assert reason =~ "2"
    end
  end
end
