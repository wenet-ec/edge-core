# edge_agent/test/edge_agent/settings/configs_test.exs
defmodule EdgeAgent.Settings.ConfigsTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Settings.Configs

  describe "get/2" do
    test "returns nil for missing key" do
      assert Configs.get("missing") == nil
    end

    test "returns the default for missing key" do
      assert Configs.get("missing", "fallback") == "fallback"
    end

    test "returns the stored value" do
      {:ok, _} = Configs.set("k", "v")
      assert Configs.get("k") == "v"
    end
  end

  describe "set/2" do
    test "returns {:ok, %Setting{}} on insert" do
      assert {:ok, setting} = Configs.set("k", "v")
      assert setting.key == "k"
      assert setting.value == "v"
    end

    test "is an upsert — second write updates the same row" do
      {:ok, _} = Configs.set("k", "first")
      {:ok, _} = Configs.set("k", "second")
      assert Configs.get("k") == "second"
    end

    test "rejects empty string value via schema validation" do
      assert {:error, changeset} = Configs.set("k", "")
      assert changeset.errors[:value]
    end
  end

  describe "delete/1" do
    test "returns {:ok, nil} for missing key" do
      assert {:ok, nil} = Configs.delete("missing")
    end

    test "removes an existing key" do
      {:ok, _} = Configs.set("k", "v")
      assert {:ok, %{key: "k"}} = Configs.delete("k")
      assert Configs.get("k") == nil
    end
  end

  describe "has_key?/1" do
    test "false for missing key" do
      refute Configs.has_key?("missing")
    end

    test "true after set, false after delete" do
      {:ok, _} = Configs.set("k", "v")
      assert Configs.has_key?("k")
      Configs.delete("k")
      refute Configs.has_key?("k")
    end
  end

  describe "all/0" do
    test "returns an empty map when nothing is set" do
      assert Configs.all() == %{}
    end

    test "returns every key/value pair" do
      {:ok, _} = Configs.set("a", "1")
      {:ok, _} = Configs.set("b", "2")
      assert Configs.all() == %{"a" => "1", "b" => "2"}
    end
  end
end
