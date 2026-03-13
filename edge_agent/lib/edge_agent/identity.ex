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
  2. **VPS/VM Detection** - If running on a virtualized host, skip persistent ID entirely
     and fall through to random UUID. VPS providers often clone base images, so
     machine-id/DMI UUIDs are frequently identical across many instances.
  3. **Persistent System ID** - Search system files for stable identifiers (bare metal only):
     - `/host/etc/machine-id` - systemd machine ID
     - `/host/var/lib/dbus/machine-id` - D-Bus machine ID
     - `/host/sys/class/dmi/id/product_uuid` - DMI product UUID
     - `/host/sys/class/dmi/id/board_serial` - Motherboard serial
     - `/host/sys/class/dmi/id/product_serial` - Product serial
     - `/host/proc/sys/kernel/random/boot_id` - Boot ID (changes per boot)
  4. **Random UUID** - Generate new random UUID

  ## VPS Detection

  Detects virtualization by reading system files (no binary execution required):
  - `/host/proc/cpuinfo` - `hypervisor` flag in CPU flags (set on KVM, Xen HVM, VMware, Hyper-V, etc.)
  - `/host/sys/class/dmi/id/sys_vendor` - Hypervisor/cloud vendor strings
  - `/host/sys/class/dmi/id/product_name` - VM product name strings
  - `/host/sys/class/dmi/id/chassis_asset_tag` - Cloud provider asset tags (Azure, DigitalOcean, Vultr)
  - `/host/sys/class/dmi/id/board_vendor` - Board vendor strings (AWS Nitro)
  - `/host/sys/hypervisor/type` - Xen paravirtualization (no CPUID hypervisor flag on Xen PV)
  - `/host/proc/vz` - OpenVZ/Virtuozzo container detection

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

      # VPS detected — automatic random ID
      iex> Identity.determine()
      {:ok, "3f2a1b0c-4d5e-6f7a-8b9c-0d1e2f3a4b5c", "random"}
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

    cond do
      use_random_id ->
        Logger.info("USE_RANDOM_ID enabled, generating random UUID")
        {:ok, Ecto.UUID.generate(), "random"}

      running_on_vps?() ->
        Logger.info("VPS/VM environment detected, generating random UUID")
        {:ok, Ecto.UUID.generate(), "random"}

      true ->
        # Try persistent ID first, fall back to random
        case try_persistent_id() do
          {:ok, id} ->
            normalized_id = normalize_to_uuid(id)
            Logger.info("Found persistent ID: #{String.slice(normalized_id, 0, 8)}...")
            {:ok, normalized_id, "persistent"}

          :error ->
            Logger.warning("No persistent ID found, generating random UUID")
            {:ok, Ecto.UUID.generate(), "random"}
        end
    end
  end

  # Returns true if the host appears to be a VPS or virtual machine.
  #
  # VPS providers frequently clone base images, meaning machine-id and DMI UUIDs
  # are often identical across many instances from the same provider. A persistent
  # ID on a VPS is therefore not reliably unique, so we fall back to a random UUID.
  #
  # Detection strategy (file reads only, no binary execution):
  #   1. /proc/cpuinfo hypervisor flag — set by nearly all type-1/type-2 hypervisors
  #      (KVM, Xen HVM, VMware, VirtualBox, Hyper-V). NOT set on Xen PV or bare metal.
  #   2. DMI sys_vendor — hypervisor or cloud vendor string (QEMU, Amazon EC2, etc.)
  #   3. DMI product_name — VM product name (VirtualBox, HVM domU, Droplet, etc.)
  #   4. DMI chassis_asset_tag — cloud provider tags (Azure, DigitalOcean, Vultr)
  #   5. DMI board_vendor — AWS Nitro uses "Amazon EC2" here
  #   6. /sys/hypervisor/type — Xen PV guests (no CPUID hypervisor flag on Xen PV)
  #   7. /proc/vz — OpenVZ/Virtuozzo containers
  defp running_on_vps? do
    cpuinfo_has_hypervisor_flag?() or
      dmi_indicates_vm?() or
      xen_hypervisor_present?() or
      openvz_present?()
  end

  # Checks /proc/cpuinfo for the x86 hypervisor CPUID bit (ECX bit 31).
  # This is set by KVM, Xen HVM, VMware, VirtualBox, Hyper-V, and bhyve.
  # One "hypervisor" token per logical CPU core will appear in flags lines.
  defp cpuinfo_has_hypervisor_flag? do
    case read_file_safely("/host/proc/cpuinfo") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.any?(fn line ->
          String.starts_with?(line, "flags") and
            String.contains?(line, "hypervisor")
        end)

      :error ->
        false
    end
  end

  # Checks DMI/SMBIOS identity files under /sys/class/dmi/id/ for known
  # hypervisor and cloud provider strings.
  defp dmi_indicates_vm? do
    vm_vendor_strings = [
      # Generic hypervisors
      "qemu",
      "kvm",
      "vmware",
      "virtualbox",
      "innotek gmbh",
      "bochs",
      "bhyve",
      "parallels",
      "xen",
      # Cloud providers
      "amazon ec2",
      "google",
      "microsoft corporation",
      "digitalocean",
      "hetzner",
      "linode",
      "vultr",
      "alibaba cloud",
      "tencent cloud",
      "ovh"
    ]

    vm_product_strings = [
      "virtualbox",
      "vmware virtual platform",
      "vmware7,1",
      "hvm domu",
      "standard pc",
      "virtual machine",
      "droplet",
      "google compute engine",
      "vserver",
      "openstack nova",
      "alibaba cloud ecs"
    ]

    vm_asset_tags = [
      # Azure hardcoded asset tag (used by cloud-init as primary Azure signal)
      "7783-7084-3265-9085-8269-3286-77",
      "digitalocean",
      "vultr",
      "openstack nova",
      "amazon ec2"
    ]

    dmi_field_matches?("/host/sys/class/dmi/id/sys_vendor", vm_vendor_strings) or
      dmi_field_matches?("/host/sys/class/dmi/id/board_vendor", vm_vendor_strings) or
      dmi_field_matches?("/host/sys/class/dmi/id/product_name", vm_product_strings) or
      dmi_field_matches?("/host/sys/class/dmi/id/chassis_asset_tag", vm_asset_tags)
  end

  defp dmi_field_matches?(path, known_strings) do
    case read_file_safely(path) do
      {:ok, content} ->
        value = content |> String.trim() |> String.downcase()
        Enum.any?(known_strings, fn s -> String.contains?(value, s) end)

      :error ->
        false
    end
  end

  # Xen PV guests don't set the CPUID hypervisor flag — the only reliable
  # signal is the presence of /sys/hypervisor/type containing "xen".
  defp xen_hypervisor_present? do
    case read_file_safely("/host/sys/hypervisor/type") do
      {:ok, content} -> String.trim(content) == "xen"
      :error -> false
    end
  end

  # OpenVZ/Virtuozzo exposes /proc/vz on the host kernel when running as a container.
  defp openvz_present? do
    File.dir?("/host/proc/vz")
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
end
