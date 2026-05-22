# edge_admin/test/edge_admin/commands/schemas/command_execution_test.exs
defmodule EdgeAdmin.Commands.Schemas.CommandExecutionTest do
  use ExUnit.Case, async: true

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Cluster

  defp execution_with_command(timeout, expires_at) do
    %CommandExecution{
      command: %Command{command_text: "uname -a", timeout: timeout, expires_at: expires_at}
    }
  end

  defp execution_without_command_preload do
    %CommandExecution{command: %NotLoaded{}}
  end

  # ---------------------------------------------------------------------------
  # command_text/1
  # ---------------------------------------------------------------------------

  describe "command_text/1" do
    test "returns command_text from preloaded command" do
      execution = execution_with_command(30_000, nil)
      assert CommandExecution.command_text(execution) == "uname -a"
    end

    test "returns nil when command is not preloaded" do
      assert CommandExecution.command_text(execution_without_command_preload()) == nil
    end

    test "returns nil when command is nil (legitimately no command association)" do
      assert CommandExecution.command_text(%CommandExecution{command: nil}) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # timeout/1
  # ---------------------------------------------------------------------------

  describe "timeout/1" do
    test "returns timeout from preloaded command" do
      assert CommandExecution.timeout(execution_with_command(60_000, nil)) == 60_000
    end

    test "returns nil when command's timeout is nil (optional field)" do
      assert CommandExecution.timeout(execution_with_command(nil, nil)) == nil
    end

    test "returns nil when command is not preloaded" do
      assert CommandExecution.timeout(execution_without_command_preload()) == nil
    end

    test "returns nil when command is nil" do
      assert CommandExecution.timeout(%CommandExecution{command: nil}) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # expires_at/1
  # ---------------------------------------------------------------------------

  describe "expires_at/1" do
    test "returns expires_at from preloaded command" do
      now = DateTime.truncate(DateTime.utc_now(), :second)
      assert CommandExecution.expires_at(execution_with_command(30_000, now)) == now
    end

    test "returns nil when command's expires_at is nil" do
      assert CommandExecution.expires_at(execution_with_command(30_000, nil)) == nil
    end

    test "returns nil when command is not preloaded" do
      assert CommandExecution.expires_at(execution_without_command_preload()) == nil
    end

    test "returns nil when command is nil" do
      assert CommandExecution.expires_at(%CommandExecution{command: nil}) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # cluster_name/1
  # ---------------------------------------------------------------------------

  describe "cluster_name/1" do
    test "returns name from preloaded cluster" do
      execution = %CommandExecution{cluster: %Cluster{name: "prod"}}
      assert CommandExecution.cluster_name(execution) == "prod"
    end

    test "returns nil when cluster is not preloaded" do
      execution = %CommandExecution{cluster: %NotLoaded{}}
      assert CommandExecution.cluster_name(execution) == nil
    end

    test "returns nil when cluster is nil (legitimately no cluster — target_all)" do
      # Executions for "target all" commands may not be tied to a single
      # cluster, in which case cluster_id and cluster are both nil.
      assert CommandExecution.cluster_name(%CommandExecution{cluster: nil}) == nil
    end
  end
end
