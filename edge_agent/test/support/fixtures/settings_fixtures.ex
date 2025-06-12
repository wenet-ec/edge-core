# edge_agent/test/support/fixtures/settings_fixtures.ex
defmodule EdgeAgent.SettingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAgent.Settings` context.
  """

  @doc """
  Generate a unique setting key.
  """
  def unique_setting_key, do: "test_key_#{System.unique_integer([:positive])}"

  @doc """
  Generate a setting.
  """
  def setting_fixture(attrs \\ %{}) do
    {:ok, setting} =
      attrs
      |> Enum.into(%{
        key: unique_setting_key(),
        value: "test_value_#{System.unique_integer([:positive])}"
      })
      |> EdgeAgent.Settings.create_setting()

    setting
  end

  @doc """
  Generate a node configuration setting.
  """
  def node_config_fixture(attrs \\ %{}) do
    default_attrs = %{
      key: "node_id",
      value: "test_node_#{System.unique_integer([:positive])}"
    }

    setting_fixture(Map.merge(default_attrs, attrs))
  end

  @doc """
  Generate multiple settings at once.
  """
  def settings_batch_fixture(settings_map) when is_map(settings_map) do
    Enum.map(settings_map, fn {key, value} ->
      setting_fixture(%{key: key, value: value})
    end)
  end

  @doc """
  Set up a complete node configuration for testing.
  """
  def node_identity_fixture do
    settings_batch_fixture(%{
      "node_id" => "test_machine_id_#{System.unique_integer([:positive])}",
      "node_id_type" => "machine_id"
    })
  end
end
