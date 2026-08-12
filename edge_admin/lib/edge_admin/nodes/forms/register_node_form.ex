# edge_admin/lib/edge_admin/nodes/forms/register_node_form.ex
defmodule EdgeAdmin.Nodes.Forms.RegisterNodeForm do
  @moduledoc """
  Form for validating agent node registration inputs.

  Validates and normalizes external API input from agents before passing it to
  the domain layer.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:node_id, :string)
    field(:network_name, :string)
    field(:http_port, :integer)
    field(:ssh_port, :integer)
    field(:host_metrics_port, :integer)
    field(:wireguard_metrics_port, :integer)
    field(:http_proxy_port, :integer)
    field(:socks5_proxy_port, :integer)
    field(:version, :string)
    field(:self_update_enabled, :boolean)
    field(:recovery_key, :string)
    field(:enrollment_key_id, :string)
  end

  @fields [
    :node_id,
    :network_name,
    :http_port,
    :ssh_port,
    :host_metrics_port,
    :wireguard_metrics_port,
    :http_proxy_port,
    :socks5_proxy_port,
    :version,
    :self_update_enabled,
    :recovery_key,
    :enrollment_key_id
  ]
  @doc """
  Validates and normalizes agent node registration parameters.

  Checks UUIDs, ports, and network-name format.
  """
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([
      :node_id,
      :network_name,
      :http_port,
      :ssh_port,
      :host_metrics_port,
      :wireguard_metrics_port,
      :http_proxy_port,
      :socks5_proxy_port,
      :version,
      :self_update_enabled,
      :enrollment_key_id
    ])
    |> validate_uuid_format(:node_id)
    |> validate_uuid_format(:enrollment_key_id)
    |> validate_network_name()
    |> validate_port(:http_port)
    |> validate_port(:ssh_port)
    |> validate_port(:host_metrics_port)
    |> validate_port(:wireguard_metrics_port)
    |> validate_port(:http_proxy_port)
    |> validate_port(:socks5_proxy_port)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validate_uuid_format(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID format"}]
      end
    end)
  end

  defp validate_network_name(changeset) do
    validate_change(changeset, :network_name, fn :network_name, value ->
      if String.starts_with?(value, "cluster-") do
        []
      else
        [network_name: "must start with 'cluster-'"]
      end
    end)
  end

  defp validate_port(changeset, field) do
    validate_number(changeset, field, greater_than: 0, less_than_or_equal_to: 65_535)
  end

  defp to_map(%__MODULE__{} = form) do
    # Convert to map with string keys, removing nil values
    %{
      "node_id" => form.node_id,
      "network_name" => form.network_name,
      "http_port" => form.http_port,
      "ssh_port" => form.ssh_port,
      "host_metrics_port" => form.host_metrics_port,
      "wireguard_metrics_port" => form.wireguard_metrics_port,
      "http_proxy_port" => form.http_proxy_port,
      "socks5_proxy_port" => form.socks5_proxy_port,
      "version" => form.version,
      "self_update_enabled" => form.self_update_enabled,
      "recovery_key" => form.recovery_key,
      "enrollment_key_id" => form.enrollment_key_id
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
