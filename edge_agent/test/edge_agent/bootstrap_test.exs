# test/edge_agent/bootstrap_test.exs
defmodule EdgeAgent.BootstrapTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Bootstrap
  alias EdgeAgent.Settings

  describe "determine_node_identity/0" do
    test "returns valid node identity when called" do
      # Test that it returns a valid result, regardless of which type
      assert {:ok, node_id, node_id_type} = Bootstrap.determine_node_identity()

      # Test the actual behavior/contract, not specific implementation
      assert node_id != nil
      assert String.length(node_id) > 0
      assert node_id_type in ["machine_id", "hardware_id", "temporary_id"]

      # Test format based on type
      case node_id_type do
        "temporary_id" ->
          assert String.match?(node_id, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i)
        "machine_id" ->
          assert String.length(node_id) > 8  # machine IDs are reasonably long
        "hardware_id" ->
          assert String.length(node_id) > 16  # hardware IDs are typically hashed
      end
    end

    test "returns consistent results when called multiple times" do
      # Test idempotency
      {:ok, node_id1, node_id_type1} = Bootstrap.determine_node_identity()
      {:ok, node_id2, node_id_type2} = Bootstrap.determine_node_identity()

      assert node_id1 == node_id2
      assert node_id_type1 == node_id_type2
    end
  end

  describe "run/0" do
    test "completes bootstrap sequence successfully" do
      assert {:ok, :bootstrap_complete} = Bootstrap.run()

      # Verify node identity was stored
      assert Settings.node_identity_configured?()

      identity = Settings.get_node_identity()
      assert identity.node_id != nil
      assert identity.node_id_type in ["machine_id", "hardware_id", "temporary_id"]
    end

    test "stores node identity in settings" do
      Bootstrap.run()

      node_id = Settings.get_node_id()
      node_id_type = Settings.get_node_id_type()

      assert node_id != nil
      assert node_id_type != nil
      assert String.length(node_id) > 0
    end
  end
end
