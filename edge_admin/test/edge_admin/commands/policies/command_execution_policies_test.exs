# edge_admin/test/edge_admin/commands/policies/command_execution_policies_test.exs
defmodule EdgeAdmin.Commands.Policies.CommandExecutionPoliciesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Policies.CommandExecutionPolicies

  # The policy authorizes :update on a command execution iff the supplied
  # node owns the execution (node.id matches execution.node_id). Used by the
  # agent-callable PATCH endpoint to ensure agents only update their own
  # executions.

  describe "authorize/1 — :update" do
    test "allowed when node.id matches execution.node_id" do
      node = %{id: "node-1"}
      execution = %{node_id: "node-1"}

      assert CommandExecutionPolicies.authorize({:update, node, execution}) == :ok
    end

    test "denied when node.id differs from execution.node_id" do
      node = %{id: "node-1"}
      execution = %{node_id: "node-2"}

      assert CommandExecutionPolicies.authorize({:update, node, execution}) ==
               {:error, :forbidden}
    end

    test "denied when ids are 'similar' but not equal (no fuzzy matching)" do
      node = %{id: "node-1"}
      execution = %{node_id: "node-1 "}

      assert CommandExecutionPolicies.authorize({:update, node, execution}) ==
               {:error, :forbidden}
    end
  end

  describe "authorize/1 — unknown actions" do
    test "any non-:update tuple is denied" do
      assert CommandExecutionPolicies.authorize({:delete, %{id: "n"}, %{node_id: "n"}}) ==
               {:error, :forbidden}
    end

    test "atom action is denied" do
      assert CommandExecutionPolicies.authorize(:read) == {:error, :forbidden}
    end

    test "missing keys on the structs is denied (pattern doesn't match)" do
      assert CommandExecutionPolicies.authorize({:update, %{}, %{node_id: "n"}}) ==
               {:error, :forbidden}

      assert CommandExecutionPolicies.authorize({:update, %{id: "n"}, %{}}) ==
               {:error, :forbidden}
    end
  end
end
