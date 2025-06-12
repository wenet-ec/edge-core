# edge_agent/test/edge_agent/settings_test.exs
defmodule EdgeAgent.SettingsTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.Settings

  import EdgeAgent.SettingsFixtures

  setup do
    # Clear any existing node identity settings before each test
    EdgeAgent.Settings.delete("node_id")
    EdgeAgent.Settings.delete("node_id_type")
    :ok
  end

  describe "settings CRUD" do
    alias EdgeAgent.Settings.Setting

    @invalid_attrs %{value: nil, key: nil}

    test "list_settings/0 returns all settings" do
      setting = setting_fixture()
      assert Settings.list_settings() == [setting]
    end

    test "get_setting!/1 returns the setting with given id" do
      setting = setting_fixture()
      assert Settings.get_setting!(setting.id) == setting
    end

    test "create_setting/1 with valid data creates a setting" do
      valid_attrs = %{value: "some value", key: "some key"}

      assert {:ok, %Setting{} = setting} = Settings.create_setting(valid_attrs)
      assert setting.value == "some value"
      assert setting.key == "some key"
    end

    test "create_setting/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Settings.create_setting(@invalid_attrs)
    end

    test "create_setting/1 with duplicate key returns error changeset" do
      setting_fixture(%{key: "duplicate_key"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Settings.create_setting(%{key: "duplicate_key", value: "different value"})

      assert "has already been taken" in errors_on(changeset).key
    end

    test "update_setting/2 with valid data updates the setting" do
      setting = setting_fixture()
      update_attrs = %{value: "some updated value", key: "some updated key"}

      assert {:ok, %Setting{} = setting} = Settings.update_setting(setting, update_attrs)
      assert setting.value == "some updated value"
      assert setting.key == "some updated key"
    end

    test "update_setting/2 with invalid data returns error changeset" do
      setting = setting_fixture()
      assert {:error, %Ecto.Changeset{}} = Settings.update_setting(setting, @invalid_attrs)
      assert setting == Settings.get_setting!(setting.id)
    end

    test "delete_setting/1 deletes the setting" do
      setting = setting_fixture()
      assert {:ok, %Setting{}} = Settings.delete_setting(setting)
      assert_raise Ecto.NoResultsError, fn -> Settings.get_setting!(setting.id) end
    end

    test "change_setting/1 returns a setting changeset" do
      setting = setting_fixture()
      assert %Ecto.Changeset{} = Settings.change_setting(setting)
    end
  end

  describe "key-value operations" do
    test "get/1 returns value for existing key" do
      setting_fixture(%{key: "test_key", value: "test_value"})

      assert Settings.get("test_key") == "test_value"
    end

    test "get/1 returns nil for non-existing key" do
      assert Settings.get("nonexistent_key") == nil
    end

    test "get/2 returns default value for non-existing key" do
      assert Settings.get("nonexistent_key", "default") == "default"
    end

    test "get/2 returns actual value when key exists, ignoring default" do
      setting_fixture(%{key: "existing_key", value: "actual_value"})

      assert Settings.get("existing_key", "default") == "actual_value"
    end

    test "set/2 creates new setting when key doesn't exist" do
      assert {:ok, %Settings.Setting{} = setting} = Settings.set("new_key", "new_value")
      assert setting.key == "new_key"
      assert setting.value == "new_value"

      # Verify it's persisted
      assert Settings.get("new_key") == "new_value"
    end

    test "set/2 updates existing setting when key exists" do
      setting_fixture(%{key: "existing_key", value: "old_value"})

      assert {:ok, %Settings.Setting{} = updated_setting} =
               Settings.set("existing_key", "new_value")

      assert updated_setting.key == "existing_key"
      assert updated_setting.value == "new_value"

      # Verify it's updated in database
      assert Settings.get("existing_key") == "new_value"

      # Verify only one setting exists with this key
      assert length(Settings.list_settings()) == 1
    end

    test "set/2 validates key and value" do
      assert {:error, %Ecto.Changeset{}} = Settings.set("", "value")
      assert {:error, %Ecto.Changeset{}} = Settings.set("key", nil)
    end

    test "delete/1 removes existing setting" do
      setting_fixture(%{key: "to_delete", value: "some_value"})

      assert {:ok, %Settings.Setting{}} = Settings.delete("to_delete")
      assert Settings.get("to_delete") == nil
    end

    test "delete/1 returns ok for non-existing key" do
      assert {:ok, nil} = Settings.delete("nonexistent_key")
    end

    test "all/0 returns all settings as a map" do
      setting_fixture(%{key: "key1", value: "value1"})
      setting_fixture(%{key: "key2", value: "value2"})
      setting_fixture(%{key: "key3", value: "value3"})

      result = Settings.all()

      assert is_map(result)

      assert result == %{
               "key1" => "value1",
               "key2" => "value2",
               "key3" => "value3"
             }
    end

    test "all/0 returns empty map when no settings exist" do
      assert Settings.all() == %{}
    end

    test "has_key?/1 returns true for existing key" do
      setting_fixture(%{key: "existing_key", value: "value"})

      assert Settings.has_key?("existing_key") == true
    end

    test "has_key?/1 returns false for non-existing key" do
      assert Settings.has_key?("nonexistent_key") == false
    end
  end

  describe "node configuration scenarios" do
    test "node identity workflow" do
      # Bootstrap sets node identity (now normalized to UUID format)
      assert {:ok, result} = Settings.set_node_identity("abc123", "machine_id")

      # Should be normalized to UUID format
      assert result.node_id != "abc123"

      assert String.match?(
               result.node_id,
               ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i
             )

      # Later retrieval returns normalized value
      assert Settings.get("node_id") == result.node_id
      assert Settings.get("node_id_type") == "machine_id"

      # Check configuration state
      config = Settings.all()
      assert config["node_id"] == result.node_id
      assert config["node_id_type"] == "machine_id"
    end

    test "configuration updates don't create duplicates" do
      # Initial config
      Settings.set("admin_endpoint", "http://admin:4000")
      assert length(Settings.list_settings()) == 1

      # Update config
      Settings.set("admin_endpoint", "http://new-admin:4000")
      assert length(Settings.list_settings()) == 1

      # Verify new value
      assert Settings.get("admin_endpoint") == "http://new-admin:4000"
    end
  end

  describe "node identity functions" do
    test "get_node_id/0 returns the node ID" do
      Settings.set("node_id", "test_node_123")

      assert Settings.get_node_id() == "test_node_123"
    end

    test "get_node_id/0 returns nil when not set" do
      assert Settings.get_node_id() == nil
    end

    test "get_node_id_type/0 returns the node ID type" do
      Settings.set("node_id_type", "machine_id")

      assert Settings.get_node_id_type() == "machine_id"
    end

    test "get_node_id_type/0 returns nil when not set" do
      assert Settings.get_node_id_type() == nil
    end

    test "set_node_identity/2 sets both node ID and type with valid UUID" do
      valid_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      assert {:ok, result} = Settings.set_node_identity(valid_uuid, "machine_id")
      assert result == %{node_id: valid_uuid, node_id_type: "machine_id"}

      assert Settings.get_node_id() == valid_uuid
      assert Settings.get_node_id_type() == "machine_id"
    end

    test "set_node_identity/2 normalizes 32-char hex to UUID format" do
      hex_32 = "bc9ebeb196a44dfd953e899a61637577"
      expected_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      assert {:ok, result} = Settings.set_node_identity(hex_32, "machine_id")
      assert result == %{node_id: expected_uuid, node_id_type: "machine_id"}

      assert Settings.get_node_id() == expected_uuid
      assert Settings.get_node_id_type() == "machine_id"
    end

    test "set_node_identity/2 normalizes 32-char hex with mixed case" do
      hex_mixed = "BC9EBEB196A44DFD953E899A61637577"
      expected_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      assert {:ok, result} = Settings.set_node_identity(hex_mixed, "hardware_id")
      assert result == %{node_id: expected_uuid, node_id_type: "hardware_id"}

      assert Settings.get_node_id() == expected_uuid
    end

    test "set_node_identity/2 handles UUID with mixed case" do
      uuid_upper = "BC9EBEB1-96A4-4DFD-953E-899A61637577"
      expected_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      assert {:ok, result} = Settings.set_node_identity(uuid_upper, "temporary_id")
      assert result == %{node_id: expected_uuid, node_id_type: "temporary_id"}
    end

    test "set_node_identity/2 validates node ID format" do
      invalid_formats = [
        "invalid-not-hex",
        # too short
        "12345",
        # too long
        "bc9ebeb196a44dfd953e899a61637577abc",
        # invalid hex chars
        "gggggggggggggggggggggggggggggggg",
        # incomplete UUID
        "bc9ebeb1-96a4-4dfd-953e",
        ""
      ]

      for invalid_id <- invalid_formats do
        assert {:error, "Invalid node ID format"} =
                 Settings.set_node_identity(invalid_id, "machine_id")
      end
    end

    test "set_node_identity/2 validates node ID" do
      assert {:error, "Node ID cannot be empty"} = Settings.set_node_identity("", "machine_id")
      assert {:error, "Node ID cannot be empty"} = Settings.set_node_identity(nil, "machine_id")
      assert {:error, "Node ID cannot be empty"} = Settings.set_node_identity("   ", "machine_id")
    end

    test "set_node_identity/2 validates node ID type" do
      valid_uuid = Ecto.UUID.generate()

      assert {:error, "Node ID type cannot be empty"} = Settings.set_node_identity(valid_uuid, "")

      assert {:error, "Node ID type cannot be empty"} =
               Settings.set_node_identity(valid_uuid, nil)

      assert {:error,
              "Invalid node ID type. Must be one of: machine_id, hardware_id, temporary_id"} =
               Settings.set_node_identity(valid_uuid, "invalid_type")
    end

    test "set_node_identity/2 validates node ID length" do
      long_id = String.duplicate("a", 256)

      assert {:error, "Node ID too long (max 255 characters)"} =
               Settings.set_node_identity(long_id, "machine_id")
    end

    test "get_node_identity/0 returns complete identity map" do
      hex_id = "bc9ebeb196a44dfd953e899a61637577"
      expected_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      Settings.set_node_identity(hex_id, "hardware_id")

      assert Settings.get_node_identity() == %{
               node_id: expected_uuid,
               node_id_type: "hardware_id"
             }
    end

    test "get_node_identity/0 returns nil values when not configured" do
      assert Settings.get_node_identity() == %{
               node_id: nil,
               node_id_type: nil
             }
    end

    test "node_identity_configured?/0 returns true when both values are set" do
      valid_uuid = Ecto.UUID.generate()
      Settings.set_node_identity(valid_uuid, "machine_id")

      assert Settings.node_identity_configured?() == true
    end

    test "node_identity_configured?/0 returns false when values are missing" do
      assert Settings.node_identity_configured?() == false

      Settings.set("node_id", "abc123")
      assert Settings.node_identity_configured?() == false

      Settings.delete("node_id")
      Settings.set("node_id_type", "machine_id")
      assert Settings.node_identity_configured?() == false
    end

    test "clear_node_identity/0 removes both values" do
      valid_uuid = Ecto.UUID.generate()
      Settings.set_node_identity(valid_uuid, "machine_id")
      assert Settings.node_identity_configured?() == true

      assert {:ok, :cleared} = Settings.clear_node_identity()
      assert Settings.node_identity_configured?() == false
      assert Settings.get_node_identity() == %{node_id: nil, node_id_type: nil}
    end

    test "set_node_identity/2 updates existing identity" do
      old_uuid = Ecto.UUID.generate()
      new_hex = "bc9ebeb196a44dfd953e899a61637577"
      expected_new_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      Settings.set_node_identity(old_uuid, "temporary_id")
      Settings.set_node_identity(new_hex, "machine_id")

      assert Settings.get_node_identity() == %{
               node_id: expected_new_uuid,
               node_id_type: "machine_id"
             }

      # Verify no duplicate entries
      assert length(Settings.list_settings()) == 2
    end

    test "set_node_identity/2 works with various valid formats" do
      test_cases = [
        # 32-char lowercase hex
        {"bc9ebeb196a44dfd953e899a61637577", "bc9ebeb1-96a4-4dfd-953e-899a61637577"},
        # 32-char uppercase hex
        {"BC9EBEB196A44DFD953E899A61637577", "bc9ebeb1-96a4-4dfd-953e-899a61637577"},
        # 32-char mixed case hex
        {"Bc9eBeb196A44dfD953e899a61637577", "bc9ebeb1-96a4-4dfd-953e-899a61637577"},
        # Valid UUID lowercase
        {"bc9ebeb1-96a4-4dfd-953e-899a61637577", "bc9ebeb1-96a4-4dfd-953e-899a61637577"},
        # Valid UUID uppercase
        {"BC9EBEB1-96A4-4DFD-953E-899A61637577", "bc9ebeb1-96a4-4dfd-953e-899a61637577"},
        # Valid UUID mixed case
        {"Bc9eBeb1-96A4-4dfD-953e-899a61637577", "bc9ebeb1-96a4-4dfd-953e-899a61637577"}
      ]

      for {input, expected} <- test_cases do
        # Clear previous settings
        Settings.clear_node_identity()

        assert {:ok, result} = Settings.set_node_identity(input, "machine_id")
        assert result.node_id == expected
        assert Settings.get_node_id() == expected
      end
    end
  end
end
