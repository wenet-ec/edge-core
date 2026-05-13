# edge_agent/test/edge_agent/settings/secrets_test.exs
defmodule EdgeAgent.Settings.SecretsTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Settings.Secrets

  describe "get/2" do
    test "returns nil for missing key" do
      assert Secrets.get("missing") == nil
    end

    test "returns the default for missing key" do
      assert Secrets.get("missing", "fallback") == "fallback"
    end

    test "returns the stored value" do
      :ok = Secrets.set("k", "v")
      assert Secrets.get("k") == "v"
    end
  end

  describe "set/2" do
    test "returns :ok" do
      assert :ok = Secrets.set("k", "v")
    end

    test "overwrites the previous value" do
      :ok = Secrets.set("k", "first")
      :ok = Secrets.set("k", "second")
      assert Secrets.get("k") == "second"
    end
  end

  describe "delete/1 and has_key?/1" do
    test "delete removes the key" do
      :ok = Secrets.set("k", "v")
      assert Secrets.has_key?("k")
      :ok = Secrets.delete("k")
      refute Secrets.has_key?("k")
      assert Secrets.get("k") == nil
    end

    test "delete on missing key is safe and idempotent" do
      assert :ok = Secrets.delete("never_existed")
      assert :ok = Secrets.delete("never_existed")
    end

    test "has_key? is false for missing key" do
      refute Secrets.has_key?("missing")
    end
  end

  test "values do not survive a reset_secrets call" do
    :ok = Secrets.set("k", "v")
    assert Secrets.get("k") == "v"
    EdgeAgent.DataCase.reset_secrets()
    assert Secrets.get("k") == nil
  end

  test "namespaced — does not leak into unrelated persistent_term keys" do
    :persistent_term.put(:unrelated_global_key, "outside_value")

    try do
      :ok = Secrets.set("k", "inside")
      EdgeAgent.DataCase.reset_secrets()

      assert :persistent_term.get(:unrelated_global_key) == "outside_value"
      assert Secrets.get("k") == nil
    after
      :persistent_term.erase(:unrelated_global_key)
    end
  end
end
