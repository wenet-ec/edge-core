# edge_agent/test/edge_agent/settings_test.exs
defmodule EdgeAgent.SettingsTest do
  use EdgeAgent.DataCase

  import EdgeAgent.SettingsFixtures

  alias EdgeAgent.Settings
  alias EdgeAgent.Settings.Setting

  # Clear ALL settings before each test, not just node identity
  setup do
    # Clean slate - delete all settings before each test
    Repo.delete_all(Setting)
    :ok
  end

  describe "settings CRUD" do
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

      assert {:ok, %Setting{} = updated_setting} = Settings.update_setting(setting, update_attrs)
      assert updated_setting.value == "some updated value"
      assert updated_setting.key == "some updated key"
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

    test "get/2 with default value" do
      assert Settings.get("nonexistent_key", "default") == "default"

      setting_fixture(%{key: "existing_key", value: "actual_value"})
      assert Settings.get("existing_key", "default") == "actual_value"
    end

    test "set/2 creates new setting when key doesn't exist" do
      assert {:ok, %Setting{} = setting} = Settings.set("new_key", "new_value")
      assert setting.key == "new_key"
      assert setting.value == "new_value"
      assert Settings.get("new_key") == "new_value"
    end

    test "set/2 updates existing setting when key exists" do
      setting_fixture(%{key: "existing_key", value: "old_value"})

      assert {:ok, %Setting{} = updated_setting} =
               Settings.set("existing_key", "new_value")

      assert updated_setting.key == "existing_key"
      assert updated_setting.value == "new_value"
      assert Settings.get("existing_key") == "new_value"
      assert length(Settings.list_settings()) == 1
    end

    test "set/2 validates key and value" do
      assert {:error, %Ecto.Changeset{}} = Settings.set("", "value")
      assert {:error, %Ecto.Changeset{}} = Settings.set("key", nil)
    end

    test "delete/1 removes existing setting" do
      setting_fixture(%{key: "to_delete", value: "some_value"})

      assert {:ok, %Setting{}} = Settings.delete("to_delete")
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

      assert result == %{
               "key1" => "value1",
               "key2" => "value2",
               "key3" => "value3"
             }
    end

    test "all/0 returns empty map when no settings exist" do
      assert Settings.all() == %{}
    end

    test "has_key?/1 returns correct boolean values" do
      setting_fixture(%{key: "existing_key", value: "value"})

      assert Settings.has_key?("existing_key") == true
      assert Settings.has_key?("nonexistent_key") == false
    end
  end

  describe "node configuration scenarios" do
    test "node identity workflow with normalization" do
      # Test with a valid 32-char hex string (this should work)
      hex_32 = "bc9ebeb196a44dfd953e899a61637577"
      assert {:ok, result} = Settings.set_node_identity(hex_32, "machine_id")

      # Should be normalized to UUID format
      assert result.id == "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      assert String.match?(
               result.id,
               ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i
             )

      # Verify persistence
      assert Settings.get("id") == result.id
      assert Settings.get("id_type") == "machine_id"

      config = Settings.all()
      assert config["id"] == result.id
      assert config["id_type"] == "machine_id"
    end

    test "configuration updates don't create duplicates" do
      Settings.set("admin_endpoint", "http://admin:4000")
      assert length(Settings.list_settings()) == 1

      Settings.set("admin_endpoint", "http://new-admin:4000")
      assert length(Settings.list_settings()) == 1
      assert Settings.get("admin_endpoint") == "http://new-admin:4000"
    end
  end

  describe "set_node_identity/2 - valid cases" do
    test "sets both node ID and type with valid UUID" do
      valid_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"
      assert {:ok, result} = Settings.set_node_identity(valid_uuid, "machine_id")
      assert result == %{id: valid_uuid, id_type: "machine_id"}

      assert Settings.get("id") == valid_uuid
      assert Settings.get("id_type") == "machine_id"
    end

    test "normalizes various valid formats" do
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
        # Clear before each iteration in the loop
        Repo.delete_all(Setting)
        assert {:ok, result} = Settings.set_node_identity(input, "machine_id")
        assert result.id == expected
        assert Settings.get("id") == expected
      end
    end

    test "updates existing identity" do
      old_uuid = Ecto.UUID.generate()
      new_hex = "bc9ebeb196a44dfd953e899a61637577"
      expected_new_uuid = "bc9ebeb1-96a4-4dfd-953e-899a61637577"

      Settings.set_node_identity(old_uuid, "temporary_id")
      Settings.set_node_identity(new_hex, "machine_id")

      assert Settings.get("id") == expected_new_uuid
      assert Settings.get("id_type") == "machine_id"

      # Verify no duplicate entries
      assert length(Settings.list_settings()) == 2
    end
  end

  describe "set_node_identity/2 - validation errors" do
    test "validates node ID cannot be empty" do
      for empty_id <- ["", nil, "   "] do
        assert {:error, "Node ID cannot be empty"} =
                 Settings.set_node_identity(empty_id, "machine_id")
      end
    end

    test "validates node ID type" do
      valid_uuid = Ecto.UUID.generate()

      assert {:error, "Node ID type cannot be empty"} =
               Settings.set_node_identity(valid_uuid, "")

      assert {:error, "Node ID type cannot be empty"} =
               Settings.set_node_identity(valid_uuid, nil)

      assert {:error, "Invalid node ID type. Must be one of: machine_id, hardware_id, temporary_id"} =
               Settings.set_node_identity(valid_uuid, "invalid_type")
    end

    test "validates node ID format" do
      invalid_formats = [
        "invalid-not-hex",
        # too short
        "12345",
        # too long
        "bc9ebeb196a44dfd953e899a61637577abc",
        # invalid hex chars
        "gggggggggggggggggggggggggggggggg",
        # incomplete UUID
        "bc9ebeb1-96a4-4dfd-953e"
      ]

      for invalid_id <- invalid_formats do
        assert {:error, "Invalid node ID format"} =
                 Settings.set_node_identity(invalid_id, "machine_id")
      end
    end

    test "validates node ID length" do
      long_id = String.duplicate("a", 256)

      assert {:error, "Node ID too long (max 255 characters)"} =
               Settings.set_node_identity(long_id, "machine_id")
    end
  end
end
