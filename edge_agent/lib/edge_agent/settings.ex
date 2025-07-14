# edge_agent/lib/edge_agent/settings.ex
defmodule EdgeAgent.Settings do
  @moduledoc """
  The Settings context.
  """

  import Ecto.Query, warn: false
  alias EdgeAgent.Repo

  alias EdgeAgent.Settings.Setting

  def list_settings do
    Repo.all(Setting)
  end

  def get_setting!(id), do: Repo.get!(Setting, id)

  def create_setting(attrs \\ %{}) do
    %Setting{}
    |> Setting.changeset(attrs)
    |> Repo.insert()
  end

  def update_setting(%Setting{} = setting, attrs) do
    setting
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  def delete_setting(%Setting{} = setting) do
    Repo.delete(setting)
  end

  def change_setting(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  def get(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> default
    end
  end

  def set(key, value) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        create_setting(%{key: key, value: value})

      existing ->
        update_setting(existing, %{value: value})
    end
  end

  def delete(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:ok, nil}
      setting -> delete_setting(setting)
    end
  end

  def all do
    Setting
    |> Repo.all()
    |> Enum.into(%{}, fn %Setting{key: key, value: value} -> {key, value} end)
  end

  def has_key?(key) do
    Setting
    |> where([s], s.key == ^key)
    |> Repo.exists?()
  end

  def set_node_identity(node_id, node_id_type) do
    with :ok <- validate_node_identity(node_id, node_id_type),
         {:ok, normalized_id} <- normalize_node_id(node_id),
         {:ok, _} <- set("id", normalized_id),
         {:ok, _} <- set("id_type", node_id_type) do
      {:ok, %{id: normalized_id, id_type: node_id_type}}
    else
      {:error, reason} -> {:error, reason}
      error -> error
    end
  end

  # PRIVATE FUNCTIONS

  defp validate_node_identity(node_id, node_id_type) do
    cond do
      is_nil(node_id) or String.trim(node_id) == "" ->
        {:error, "Node ID cannot be empty"}

      is_nil(node_id_type) or String.trim(node_id_type) == "" ->
        {:error, "Node ID type cannot be empty"}

      node_id_type not in ["machine_id", "hardware_id", "temporary_id"] ->
        {:error, "Invalid node ID type. Must be one of: machine_id, hardware_id, temporary_id"}

      String.length(node_id) > 255 ->
        {:error, "Node ID too long (max 255 characters)"}

      true ->
        :ok
    end
  end

  defp normalize_node_id(node_id) do
    case Ecto.UUID.cast(node_id) do
      {:ok, uuid} ->
        # Already in proper format
        {:ok, uuid}

      :error ->
        # Try to convert from 32-char hex to UUID format
        case format_hex_to_uuid(node_id) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, "Invalid node ID format"}
        end
    end
  end

  defp format_hex_to_uuid(hex_string) do
    # Remove any existing dashes and convert to lowercase
    clean_hex =
      hex_string
      |> String.replace("-", "")
      |> String.downcase()

    # Check if it's a valid 32-character hex string
    if String.match?(clean_hex, ~r/^[a-f0-9]{32}$/) do
      # Insert dashes at proper UUID positions: 8-4-4-4-12
      uuid =
        String.slice(clean_hex, 0, 8) <>
          "-" <>
          String.slice(clean_hex, 8, 4) <>
          "-" <>
          String.slice(clean_hex, 12, 4) <>
          "-" <>
          String.slice(clean_hex, 16, 4) <>
          "-" <>
          String.slice(clean_hex, 20, 12)

      {:ok, uuid}
    else
      :error
    end
  end
end
