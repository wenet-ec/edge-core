# edge_admin/test/edge_admin/commands/checks/non_finalized_command_executions_check_test.exs
defmodule EdgeAdmin.Commands.Checks.NonFinalizedCommandExecutionsCheckTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Commands.Checks.NonFinalizedCommandExecutionsCheck
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @admin_completed_at ~U[2026-09-25 00:00:00Z]
  # helpers

  # See cluster_filters_test for rationale: monotonic ints, not random, so
  # birthday-paradox collisions on the small `100.64.X.0/24` space disappear.
  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  defp unique_ipv4_range do
    n = unique_id()
    octet2 = 64 + rem(div(n, 256), 64)
    octet3 = rem(n, 256)
    "100.#{octet2}.#{octet3}.0/24"
  end

  defp unique_ipv6_range, do: "fd7a:91c2:4e8b:#{rem(unique_id(), 65_536)}::/64"

  defp insert_cluster do
    Repo.insert!(
      struct(Cluster, %{
        id: Ecto.UUID.generate(),
        name: "cluster-#{unique_id()}",
        ipv4_range: unique_ipv4_range(),
        ipv6_range: unique_ipv6_range()
      })
    )
  end

  defp insert_node(cluster_id) do
    Repo.insert!(
      struct(Node, %{
        id: Ecto.UUID.generate(),
        cluster_id: cluster_id,
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
        proxy_password: Ecto.UUID.generate(),
        ingress_public_key: unique_ingress_public_key()
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

  defp insert_execution(command_id, node_id, status, attrs \\ %{}) do
    Repo.insert!(
      struct(
        CommandExecution,
        Map.merge(%{id: Ecto.UUID.generate(), command_id: command_id, node_id: node_id, status: status}, attrs)
      )
    )
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
