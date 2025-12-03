# edge_agent/lib/edge_agent/identity.ex
defmodule EdgeAgent.Identity do
  @moduledoc """
  Node identity determination.

  Determines a stable node ID from system information with the following priority:
  1. Check Settings database for existing node_id
  2. Try to find persistent ID (machine-id or hardware-id)
  3. Fall back to random UUID

  Can skip persistent ID search via USE_RANDOM_ID env vars.
  """

  require Logger

  alias EdgeAgent.Settings

  @doc """
  Determine node identity.

  Returns `{:ok, node_id, id_type}` where:
  - `node_id` is the node identifier string
  - `id_type` is either `"persistent"` or `"random"`

  Priority:
  1. Existing ID in Settings table
  2. Persistent ID from system (unless USE_RANDOM_ID is true)
  3. Random UUID generation
  """
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

    cond do
      use_random_id ->
        Logger.info("USE_RANDOM_ID enabled, generating random UUID")
        {:ok, Ecto.UUID.generate(), "random"}

      true ->
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
      <<p1::binary-size(8), p2::binary-size(4), p3::binary-size(4), p4::binary-size(4),
        p5::binary-size(12)>> = hex32

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
