defmodule EdgeAgent.SettingsTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Settings

  # -----------------------------------------------------------------------
  # get/2 and set/2 — generic key-value
  # -----------------------------------------------------------------------

  describe "get/2 and set/2" do
    test "returns nil for missing key by default" do
      assert Settings.get("nonexistent") == nil
    end

    test "returns custom default for missing key" do
      assert Settings.get("nonexistent", "fallback") == "fallback"
    end

    test "set then get returns the value" do
      {:ok, _} = Settings.set("my_key", "my_value")
      assert Settings.get("my_key") == "my_value"
    end

    test "set is upsert — second set updates the value" do
      {:ok, _} = Settings.set("my_key", "first")
      {:ok, _} = Settings.set("my_key", "second")
      assert Settings.get("my_key") == "second"
    end

    test "set returns {:ok, setting}" do
      assert {:ok, setting} = Settings.set("k", "v")
      assert setting.key == "k"
      assert setting.value == "v"
    end

    test "different keys are independent" do
      {:ok, _} = Settings.set("key_a", "value_a")
      {:ok, _} = Settings.set("key_b", "value_b")
      assert Settings.get("key_a") == "value_a"
      assert Settings.get("key_b") == "value_b"
    end

    test "empty string value is rejected by the schema (validate_required on :value)" do
      assert {:error, changeset} = Settings.set("empty_val", "")
      assert changeset.errors[:value]
    end
  end

  # -----------------------------------------------------------------------
  # delete/1
  # -----------------------------------------------------------------------

  describe "delete/1" do
    test "returns {:ok, nil} for nonexistent key" do
      assert {:ok, nil} = Settings.delete("nonexistent")
    end

    test "deletes existing key and returns {:ok, setting}" do
      {:ok, _} = Settings.set("to_delete", "bye")
      assert {:ok, setting} = Settings.delete("to_delete")
      assert setting.key == "to_delete"
    end

    test "key is gone after delete" do
      {:ok, _} = Settings.set("gone", "soon")
      Settings.delete("gone")
      assert Settings.get("gone") == nil
    end

    test "deleting nonexistent key twice is safe" do
      assert {:ok, nil} = Settings.delete("never_existed")
      assert {:ok, nil} = Settings.delete("never_existed")
    end
  end

  # -----------------------------------------------------------------------
  # has_key?/1
  # -----------------------------------------------------------------------

  describe "has_key?/1" do
    test "returns false for missing key" do
      refute Settings.has_key?("missing")
    end

    test "returns true after setting a key" do
      {:ok, _} = Settings.set("present", "yes")
      assert Settings.has_key?("present")
    end

    test "returns false after deleting a key" do
      {:ok, _} = Settings.set("temp", "value")
      Settings.delete("temp")
      refute Settings.has_key?("temp")
    end
  end

  # -----------------------------------------------------------------------
  # all/0
  # -----------------------------------------------------------------------

  describe "all/0" do
    test "returns empty map when no settings exist" do
      assert Settings.all() == %{}
    end

    test "returns all keys and values" do
      {:ok, _} = Settings.set("a", "1")
      {:ok, _} = Settings.set("b", "2")
      result = Settings.all()
      assert result["a"] == "1"
      assert result["b"] == "2"
    end

    test "returns a plain map with string keys" do
      {:ok, _} = Settings.set("x", "y")
      result = Settings.all()
      assert is_map(result)
      assert Map.has_key?(result, "x")
    end
  end

  # -----------------------------------------------------------------------
  # Typed accessors — simple string passthrough
  # -----------------------------------------------------------------------

  describe "node_id accessors" do
    test "get_node_id returns nil when not set" do
      assert Settings.get_node_id() == nil
    end

    test "set_node_id then get_node_id roundtrips" do
      {:ok, _} = Settings.set_node_id("abc-123")
      assert Settings.get_node_id() == "abc-123"
    end
  end

  describe "id_type accessors" do
    test "get_id_type returns nil when not set" do
      assert Settings.get_id_type() == nil
    end

    test "set_id_type then get_id_type roundtrips" do
      {:ok, _} = Settings.set_id_type("persistent")
      assert Settings.get_id_type() == "persistent"
    end
  end

  describe "api_token accessors" do
    test "get_api_token returns nil when not set" do
      assert Settings.get_api_token() == nil
    end

    test "set_api_token then get_api_token roundtrips" do
      {:ok, _} = Settings.set_api_token("tok-abc")
      assert Settings.get_api_token() == "tok-abc"
    end
  end

  describe "proxy_password accessors" do
    test "get_proxy_password returns nil when not set" do
      assert Settings.get_proxy_password() == nil
    end

    test "set_proxy_password then get_proxy_password roundtrips" do
      {:ok, _} = Settings.set_proxy_password("s3cr3t")
      assert Settings.get_proxy_password() == "s3cr3t"
    end
  end

  # -----------------------------------------------------------------------
  # admin_urls — JSON encode/decode
  # -----------------------------------------------------------------------

  describe "admin_urls accessors" do
    test "get_admin_urls returns empty list when not set" do
      assert Settings.get_admin_urls() == []
    end

    test "set_admin_urls then get_admin_urls roundtrips a list" do
      urls = ["http://admin1:44000", "http://admin2:44000"]
      {:ok, _} = Settings.set_admin_urls(urls)
      assert Settings.get_admin_urls() == urls
    end

    test "set_admin_urls with empty list roundtrips" do
      {:ok, _} = Settings.set_admin_urls([])
      assert Settings.get_admin_urls() == []
    end

    test "set_admin_urls with single URL roundtrips" do
      {:ok, _} = Settings.set_admin_urls(["http://admin:44000"])
      assert Settings.get_admin_urls() == ["http://admin:44000"]
    end

    test "get_admin_urls returns empty list for corrupted JSON" do
      # Store invalid JSON directly
      {:ok, _} = Settings.set("admin_urls", "not valid json {{{")
      assert Settings.get_admin_urls() == []
    end

    test "stored value is a JSON string (not a raw list)" do
      {:ok, _} = Settings.set_admin_urls(["http://admin:44000"])
      raw = Settings.get("admin_urls")
      assert is_binary(raw)
      assert {:ok, _} = Jason.decode(raw)
    end
  end

  # -----------------------------------------------------------------------
  # relay_admin_name — nil handling
  # -----------------------------------------------------------------------

  describe "relay_admin_name accessors" do
    test "get_relay_admin_name returns nil when not set" do
      assert Settings.get_relay_admin_name() == nil
    end

    test "set_relay_admin_name then get roundtrips" do
      {:ok, _} = Settings.set_relay_admin_name("admin-abc123")
      assert Settings.get_relay_admin_name() == "admin-abc123"
    end

    test "set_relay_admin_name(nil) fails — empty string rejected by schema" do
      assert {:error, changeset} = Settings.set_relay_admin_name(nil)
      assert changeset.errors[:value]
    end

    test "set_relay_admin_name can overwrite previous value" do
      {:ok, _} = Settings.set_relay_admin_name("admin-old")
      {:ok, _} = Settings.set_relay_admin_name("admin-new")
      assert Settings.get_relay_admin_name() == "admin-new"
    end
  end

  # -----------------------------------------------------------------------
  # last_check_self_update_at — ISO8601 encode/decode
  # -----------------------------------------------------------------------

  describe "last_check_self_update_at accessors" do
    test "get_last_check_self_update_at returns nil when not set" do
      assert Settings.get_last_check_self_update_at() == nil
    end

    test "set then get roundtrips a DateTime" do
      dt = DateTime.truncate(~U[2026-01-15 12:30:00Z], :second)
      {:ok, _} = Settings.set_last_check_self_update_at(dt)
      result = Settings.get_last_check_self_update_at()
      assert %DateTime{} = result
      assert DateTime.compare(result, dt) == :eq
    end

    test "stored value is an ISO8601 string" do
      dt = ~U[2026-01-15 12:30:00Z]
      {:ok, _} = Settings.set_last_check_self_update_at(dt)
      raw = Settings.get("last_check_self_update_at")
      assert is_binary(raw)
      assert {:ok, _, _} = DateTime.from_iso8601(raw)
    end

    test "returns nil for corrupted stored value" do
      {:ok, _} = Settings.set("last_check_self_update_at", "not-a-datetime")
      assert Settings.get_last_check_self_update_at() == nil
    end

    test "can overwrite with newer datetime" do
      dt1 = ~U[2026-01-01 00:00:00Z]
      dt2 = ~U[2026-06-01 00:00:00Z]
      {:ok, _} = Settings.set_last_check_self_update_at(dt1)
      {:ok, _} = Settings.set_last_check_self_update_at(dt2)
      result = Settings.get_last_check_self_update_at()
      assert DateTime.compare(result, dt2) == :eq
    end
  end
end
