# edge_agent/lib/edge_agent/identity.ex
defmodule EdgeAgent.Identity do
  @moduledoc """
  Node identity determination for edge agents.

  This module determines a stable, unique identifier for the agent node by attempting
  to extract persistent system identifiers (machine-id, hardware UUID) or generating
  a random UUID as fallback. The identity persists across restarts via the Settings database.

  ## Key Concepts

  - **Persistent ID**: System-level identifier that survives reboots (machine-id, DMI UUID)
  - **Random ID**: Fallback UUID generated when persistent ID unavailable
  - **ID Normalization**: All IDs converted to UUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
  - **Settings Persistence**: Identity stored in database for consistency across restarts

  ## Identity Priority

  The module follows this priority order:

  1. **Existing ID in Settings** - Use stored node_id and id_type from previous runs
  2. **Persistent System ID** - Search system files for stable identifiers:
     - `/host/etc/machine-id` - systemd machine ID
     - `/host/var/lib/dbus/machine-id` - D-Bus machine ID
     - `/host/sys/class/dmi/id/product_uuid` - DMI product UUID
     - `/host/sys/class/dmi/id/board_serial` - Motherboard serial
     - `/host/sys/class/dmi/id/product_serial` - Product serial
     - `/host/proc/sys/kernel/random/boot_id` - Boot ID (changes per boot)
  3. **Random UUID** - Generate new random UUID

  ## Configuration

  - `:use_random_id` - Set to `true` to skip persistent ID search (useful for testing)

  ## ID Normalization

  All identifiers are normalized to UUID format:
  - Strip non-hex characters
  - Take first 32 hex characters (or pad with zeros)
  - Insert hyphens at positions 8-4-4-4-12

  Example:
  - Raw machine-id: `a1b2c3d4e5f6708192a3b4c5d6e7f809`
  - Normalized: `a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809`

  ## Validation

  Persistent IDs are validated to exclude invalid/placeholder values:
  - Too short (< 8 bytes) or too long (> 128 bytes)
  - Empty strings
  - Known placeholder values ("Not Specified", "To be filled by O.E.M.", etc.)
  - All-zero UUIDs

  ## Examples

      # First run - determine new identity
      iex> Identity.determine()
      {:ok, "a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809", "persistent"}

      # Subsequent runs - use stored identity
      iex> Identity.determine()
      {:ok, "a1b2c3d4-e5f6-7081-92a3-b4c5d6e7f809", "persistent"}

      # Force random ID
      Application.put_env(:edge_agent, :use_random_id, true)
      iex> Identity.determine()
      {:ok, "7c8d9e0f-1a2b-3c4d-5e6f-708192a3b4c5", "random"}
  """

  alias EdgeAgent.Settings

  require Logger

  @doc """
  Determine node identity.

  Returns `{:ok, node_id, id_type}` where:
  - `node_id` is the node identifier string (UUID format)
  - `id_type` is either `"persistent"` or `"random"`

  Priority:
  1. Existing ID in Settings table
  2. Persistent ID from system (unless `:use_random_id` is `true`)
  3. Random UUID generation

  Always returns `{:ok, node_id, id_type}` - never fails.
  """
  @spec determine() :: {:ok, String.t(), String.t()}
  def determine do
    # Check if we already have an ID in the database
    with node_id when not is_nil(node_id) <- Settings.get_node_id(),
         id_type when not is_nil(id_type) <- Settings.get_id_type(),
         true <- id_type in ["persistent", "random"] do
      # Found valid existing ID
      Logger.info("Found existing node identity: #{String.slice(node_id, 0, 8)}... (#{id_type})")
      {:ok, node_id, id_type}
    else
      _ ->
        # Missing or invalid ID/type, determine new one
        Logger.warning("Invalid or missing node identity in database, regenerating...")
        determine_new_identity()
    end
  end

  # Determine a new identity (not in database yet)
  defp determine_new_identity do
    use_random_id = Application.get_env(:edge_agent, :use_random_id, false)

    if use_random_id do
      Logger.info("USE_RANDOM_ID enabled, generating random UUID")
      {:ok, Ecto.UUID.generate(), "random"}
    else
      # Try persistent ID first, fall back to random
      case try_persistent_id() do
        {:ok, id} ->
          # Normalize to UUID format with hyphens
          normalized_id = normalize_to_uuid(id)
          Logger.info("Found persistent ID: #{String.slice(normalized_id, 0, 8)}...")
          {:ok, normalized_id, "persistent"}

        :error ->
          Logger.warning("No persistent ID found, generating random UUID")
          {:ok, Ecto.UUID.generate(), "random"}
      end
    end
  end

  # Normalize a string to UUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
  defp normalize_to_uuid(id) do
    # Check if already in UUID format
    if String.contains?(id, "-") and String.match?(id, ~r/^[a-f0-9-]{36}$/i) do
      String.downcase(id)
    else
      # Remove any non-hex characters and convert to lowercase
      clean_hex =
        id
        |> String.replace(~r/[^a-fA-F0-9]/, "")
        |> String.downcase()

      # Take first 32 hex characters (or pad if shorter)
      hex32 =
        case String.length(clean_hex) do
          len when len >= 32 ->
            String.slice(clean_hex, 0, 32)

          len ->
            # Pad with zeros if shorter than 32 characters
            clean_hex <> String.duplicate("0", 32 - len)
        end

      # Insert hyphens at UUID positions: 8-4-4-4-12
      <<p1::binary-size(8), p2::binary-size(4), p3::binary-size(4), p4::binary-size(4), p5::binary-size(12)>> = hex32

      "#{p1}-#{p2}-#{p3}-#{p4}-#{p5}"
    end
  end

  defp try_persistent_id do
    persistent_id_paths = [
      "/host/etc/machine-id",
      "/host/var/lib/dbus/machine-id",
      "/host/sys/class/dmi/id/product_uuid",
      "/host/sys/class/dmi/id/board_serial",
      "/host/sys/class/dmi/id/product_serial",
      "/host/proc/sys/kernel/random/boot_id"
    ]

    Enum.find_value(persistent_id_paths, :error, fn path ->
      case read_file_safely(path) do
        {:ok, content} ->
          cleaned = String.trim(content)

          if valid_persistent_id?(cleaned) do
            Logger.debug("Found persistent ID at #{path}")
            {:ok, cleaned}
          else
            false
          end

        :error ->
          false
      end
    end)
  end

  defp read_file_safely(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, _reason} -> :error
    end
  end

  defp valid_persistent_id?(id) when is_binary(id) do
    byte_size(id) >= 8 and
      byte_size(id) <= 128 and
      id != "" and
      id != "Not Specified" and
      id != "Default string" and
      id != "To be filled by O.E.M." and
      id != "System Serial Number" and
      id != "0" and
      id != "00000000-0000-0000-0000-000000000000"
  end

  defp valid_persistent_id?(_), do: false
end
