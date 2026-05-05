# edge_admin/test/edge_admin/events/webhooks/filter_test.exs
defmodule EdgeAdmin.Events.Webhooks.FilterTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Filter

  describe "matches?/2 — exact and wildcard" do
    test "exact match" do
      assert Filter.matches?("edge.node.registered", "edge.node.registered")
      refute Filter.matches?("edge.node.registered", "edge.node.reregistered")
    end

    test "trailing wildcard" do
      assert Filter.matches?("edge.node.*", "edge.node.registered")
      assert Filter.matches?("edge.node.*", "edge.node.status_changed")
      refute Filter.matches?("edge.node.*", "edge.command_execution.completed")
      # `*` matches any chars; "edge.node" has no trailing dot so the literal
      # "." in the pattern doesn't line up
      refute Filter.matches?("edge.node.*", "edge.node")
    end

    test "wildcard in middle position" do
      assert Filter.matches?("edge.*.registered", "edge.node.registered")
      assert Filter.matches?("edge.*.completed", "edge.command_execution.completed")
      refute Filter.matches?("edge.*.registered", "edge.command_execution.completed")
    end

    test "leading wildcard" do
      assert Filter.matches?("*.node.registered", "edge.node.registered")
      refute Filter.matches?("*.node.registered", "edge.command_execution.completed")
    end

    test "lone `*` matches everything" do
      assert Filter.matches?("*", "edge.node.registered")
      assert Filter.matches?("*", "anything.at.all")
    end

    test "wildcard greedily includes dots — deeper hierarchies match" do
      # Distinct from NATS-style segment-only wildcards: `*` matches any chars
      # including dots, so a middle wildcard can absorb multiple segments.
      assert Filter.matches?("edge.*.completed", "edge.command_execution.foo.completed")
    end
  end

  describe "validate/1 — syntax" do
    test "rejects empty string" do
      assert {:error, msg} = Filter.validate("")
      assert msg =~ "empty"
    end

    test "rejects leading/trailing/double dots" do
      assert {:error, _} = Filter.validate(".edge.node.registered")
      assert {:error, _} = Filter.validate("edge.node.registered.")
      assert {:error, _} = Filter.validate("edge..node.registered")
    end

    test "rejects uppercase and regex meta characters" do
      assert {:error, _} = Filter.validate("edge.Node.registered")
      assert {:error, _} = Filter.validate("edge.node.regis^tered")
      assert {:error, _} = Filter.validate("edge.node.>")
      assert {:error, _} = Filter.validate("edge.node.registered?")
    end
  end

  describe "validate/1 — catalog cross-check" do
    test "accepts patterns that match a known event type" do
      assert :ok = Filter.validate("edge.node.registered")
      assert :ok = Filter.validate("edge.node.*")
      assert :ok = Filter.validate("edge.*")
      assert :ok = Filter.validate("*")
    end

    test "rejects patterns matching no current event type" do
      # No event in the catalog ends in `.foo`
      assert {:error, msg} = Filter.validate("edge.node.foo")
      assert msg =~ "matches no current event type"

      # Hypothetical domain not in the catalog yet
      assert {:error, _} = Filter.validate("edge.deployment.*")
    end
  end
end
