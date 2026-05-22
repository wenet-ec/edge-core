# edge_admin/test/edge_admin/commands/views/command_execution_view_test.exs
defmodule EdgeAdmin.Commands.Views.CommandExecutionViewTest do
  use ExUnit.Case, async: true

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Views.CommandExecutionView
  alias EdgeAdmin.Nodes.Schemas.Cluster

  defp execution_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    expiry = DateTime.add(now, 3600, :second)

    cluster = %Cluster{id: "cluster-uuid-1", name: "prod"}
    command = %Command{id: "command-uuid-1", command_text: "uname -a", timeout: 30_000, expires_at: expiry}

    base = %CommandExecution{
      id: "execution-uuid-1",
      command_id: command.id,
      command: command,
      node_id: "node-uuid-1",
      cluster_id: cluster.id,
      cluster: cluster,
      target_all: false,
      status: :pending,
      output: nil,
      exit_code: nil,
      sent_at: nil,
      completed_at: nil,
      cancelled_at: nil,
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values, including virtuals from preloads" do
      execution = execution_fixture()

      result = CommandExecutionView.render(execution)

      # Identity / direct fields.
      assert result.id == execution.id
      assert result.command_id == "command-uuid-1"
      assert result.node_id == "node-uuid-1"
      assert result.target_all == false
      assert result.status == "pending"
      assert result.output == nil
      assert result.exit_code == nil

      # Virtuals derived from preloaded command.
      assert result.command_text == "uname -a"
      assert result.timeout == 30_000
      assert result.expires_at == execution.command.expires_at

      # Virtuals derived from preloaded cluster.
      assert result.cluster_name == "prod"

      # Timestamps.
      assert result.sent_at == nil
      assert result.completed_at == nil
      assert result.cancelled_at == nil
      assert result.inserted_at == execution.inserted_at
      assert result.updated_at == execution.updated_at
    end

    test "completed execution carries output, exit_code, and timestamps" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      execution =
        execution_fixture(%{
          status: :completed,
          output: "Linux 6.1.0",
          exit_code: 0,
          sent_at: now,
          completed_at: now
        })

      result = CommandExecutionView.render(execution)

      assert result.status == "completed"
      assert result.output == "Linux 6.1.0"
      assert result.exit_code == 0
      assert result.sent_at == now
      assert result.completed_at == now
    end

    test "missing command preload → command_text/timeout/expires_at fall through to nil" do
      # The schema helpers explicitly fall back to nil when associations are
      # not preloaded. The view must not crash when callers forget the preload.
      execution = execution_fixture(%{command: %NotLoaded{}})

      result = CommandExecutionView.render(execution)

      assert result.command_text == nil
      assert result.timeout == nil
      assert result.expires_at == nil
    end

    test "missing cluster preload → cluster_name falls through to nil" do
      execution = execution_fixture(%{cluster: %NotLoaded{}})

      assert CommandExecutionView.render(execution).cluster_name == nil
    end

    test "nil cluster (legitimately no cluster) → cluster_name is nil" do
      # cluster is nullable in the schema (cluster_id can be nil). The schema
      # helper handles this via its catch-all clause.
      execution = execution_fixture(%{cluster: nil, cluster_id: nil})

      assert CommandExecutionView.render(execution).cluster_name == nil
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = CommandExecutionView.render(execution_fixture())

      expected_keys = Enum.sort(~w(
          id command_id node_id cluster_name target_all status command_text timeout
          output exit_code sent_at completed_at cancelled_at expires_at
          inserted_at updated_at
        )a)

      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
