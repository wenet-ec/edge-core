defmodule EdgeAgent.IdentityTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Identity
  alias EdgeAgent.Settings

  defp with_use_random_id(value, fun) do
    old = Application.get_env(:edge_agent, :use_random_id)
    Application.put_env(:edge_agent, :use_random_id, value)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:edge_agent, :use_random_id)
      else
        Application.put_env(:edge_agent, :use_random_id, old)
      end
    end
  end

  # -----------------------------------------------------------------------
  # determine/0 — stored identity path (no filesystem, no randomness)
  # -----------------------------------------------------------------------

  describe "determine/0 — stored identity returned as-is" do
    test "returns stored persistent node_id and id_type without touching filesystem" do
      {:ok, _} = Settings.set_node_id("a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809")
      {:ok, _} = Settings.set_id_type("persistent")

      assert {:ok, "a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809", "persistent"} = Identity.determine()
    end

    test "returns stored random node_id and id_type" do
      {:ok, _} = Settings.set_node_id("ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb")
      {:ok, _} = Settings.set_id_type("random")

      assert {:ok, "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb", "random"} = Identity.determine()
    end

    test "node_id value is preserved exactly as stored" do
      stored_id = "11111111-2222-3333-4444-555555555555"
      {:ok, _} = Settings.set_node_id(stored_id)
      {:ok, _} = Settings.set_id_type("persistent")

      {:ok, returned_id, _} = Identity.determine()
      assert returned_id == stored_id
    end

    test "id_type value is preserved exactly as stored" do
      {:ok, _} = Settings.set_node_id("a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809")
      {:ok, _} = Settings.set_id_type("random")

      {:ok, _, returned_type} = Identity.determine()
      assert returned_type == "random"
    end
  end

  # -----------------------------------------------------------------------
  # determine/0 — falls through to new identity when Settings incomplete
  # -----------------------------------------------------------------------

  describe "determine/0 — falls through to random when Settings incomplete" do
    test "missing node_id generates a new UUID" do
      # node_id absent, id_type present — should fall through
      {:ok, _} = Settings.set_id_type("persistent")

      with_use_random_id(true, fn ->
        assert {:ok, node_id, "random"} = Identity.determine()
        assert is_binary(node_id)
        assert String.match?(node_id, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
      end)
    end

    test "missing id_type generates a new identity" do
      {:ok, _} = Settings.set_node_id("a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809")
      # id_type absent

      with_use_random_id(true, fn ->
        assert {:ok, _node_id, "random"} = Identity.determine()
      end)
    end

    test "invalid id_type falls through to new identity" do
      {:ok, _} = Settings.set_node_id("a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809")
      {:ok, _} = Settings.set_id_type("unknown")

      with_use_random_id(true, fn ->
        assert {:ok, _node_id, "random"} = Identity.determine()
      end)
    end

    test "empty Settings generates a new identity" do
      # Nothing stored at all
      with_use_random_id(true, fn ->
        assert {:ok, _node_id, "random"} = Identity.determine()
      end)
    end
  end

  # -----------------------------------------------------------------------
  # determine/0 — always returns {:ok, _, _}
  # -----------------------------------------------------------------------

  describe "determine/0 — never fails" do
    test "always returns {:ok, id, type} tuple" do
      with_use_random_id(true, fn ->
        result = Identity.determine()
        assert {:ok, id, type} = result
        assert is_binary(id)
        assert type in ["persistent", "random"]
      end)
    end

    test "generated random id is in UUID format" do
      with_use_random_id(true, fn ->
        {:ok, node_id, "random"} = Identity.determine()
        uuid_regex = ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/
        assert String.match?(node_id, uuid_regex), "Expected UUID format, got: #{node_id}"
      end)
    end

    test "two calls with stored identity return the same id" do
      {:ok, _} = Settings.set_node_id("a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809")
      {:ok, _} = Settings.set_id_type("persistent")

      {:ok, id1, _} = Identity.determine()
      {:ok, id2, _} = Identity.determine()
      assert id1 == id2
    end
  end
end
