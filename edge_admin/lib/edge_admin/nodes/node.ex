# edge_admin/lib/edge_admin/nodes/node.ex
defmodule EdgeAdmin.Nodes.Node do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "nodes" do
    field(:status, :string)
    field(:vpn_ip, :string)
    field(:last_seen_at, :utc_datetime)
    field(:id_type, :string)

    # Virtual field - computed from UUID
    field(:vpn_hostname, :string, virtual: true)

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:id, :vpn_ip, :last_seen_at, :status, :id_type])
    |> normalize_hardware_id()
    |> validate_required([:id])
    |> validate_inclusion(:id_type, ["machine_id", "hardware_id", "temporary_id"])
    |> unique_constraint(:id, name: :nodes_pkey)
    |> put_vpn_hostname()
  end

  # Convert hardware ID to proper UUID format
  defp normalize_hardware_id(%Ecto.Changeset{} = changeset) do
    case get_change(changeset, :id) do
      nil ->
        changeset

      hardware_id when is_binary(hardware_id) ->
        case format_hardware_id_to_uuid(hardware_id) do
          {:ok, uuid} -> put_change(changeset, :id, uuid)
          {:error, _} -> add_error(changeset, :id, "invalid hardware ID format")
        end

      _ ->
        changeset
    end
  end

  defp normalize_hardware_id(changeset), do: changeset

  @doc """
  Converts a hardware ID to UUID format.
  Handles hex strings with or without dashes.
  """
  def format_hardware_id_to_uuid(hardware_id) when is_binary(hardware_id) do
    # Remove any existing dashes and convert to lowercase
    clean_hex =
      hardware_id
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
      # If it's not a 32-char hex string, try to parse as existing UUID
      case Ecto.UUID.cast(hardware_id) do
        {:ok, uuid} -> {:ok, uuid}
        :error -> {:error, "invalid hardware ID format"}
      end
    end
  end

  defp put_vpn_hostname(%Ecto.Changeset{data: %{id: id}} = changeset) when not is_nil(id) do
    put_change(changeset, :vpn_hostname, "node-#{id}")
  end

  defp put_vpn_hostname(changeset), do: changeset

  def vpn_hostname(%__MODULE__{id: id}) when not is_nil(id) do
    "node-#{id}"
  end

  def vpn_hostname(_), do: nil

  def populate_virtual_fields(%__MODULE__{} = node) do
    %{node | vpn_hostname: vpn_hostname(node)}
  end

  @doc """
  Helper to check if a node is temporary (for cleanup logic)
  """
  def temporary?(%__MODULE__{id_type: "temporary_id"}), do: true
  def temporary?(_), do: false

  @doc """
  Helper to check if a node is persistent
  """
  def persistent?(%__MODULE__{id_type: id_type}) when id_type in ["machine_id", "hardware_id"],
    do: true

  def persistent?(_), do: false
end
