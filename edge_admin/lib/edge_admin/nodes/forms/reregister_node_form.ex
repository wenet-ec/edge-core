# edge_admin/lib/edge_admin/nodes/forms/reregister_node_form.ex
defmodule EdgeAdmin.Nodes.Forms.ReregisterNodeForm do
  @moduledoc """
  Validates the metadata sent when an authenticated Agent re-registers.

  Re-registration deliberately excludes the node ID and recovery key because
  the authenticated route already identifies the node.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:network_name, :string)
    field(:http_port, :integer)
    field(:ssh_port, :integer)
    field(:host_metrics_port, :integer)
    field(:wireguard_metrics_port, :integer)
    field(:http_proxy_port, :integer)
    field(:socks5_proxy_port, :integer)
    field(:version, :string)
    field(:self_update_enabled, :boolean)
  end

  @fields [
    :network_name,
    :http_port,
    :ssh_port,
    :host_metrics_port,
    :wireguard_metrics_port,
    :http_proxy_port,
    :socks5_proxy_port,
    :version,
    :self_update_enabled
  ]

  @doc "Validates and normalizes authenticated Agent re-registration attributes."
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
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

  defp validate_network_name(changeset) do
    validate_change(changeset, :network_name, fn :network_name, value ->
      if String.starts_with?(value, "cluster-"), do: [], else: [network_name: "must start with 'cluster-'"]
    end)
  end

  defp validate_port(changeset, field) do
    validate_number(changeset, field, greater_than: 0, less_than_or_equal_to: 65_535)
  end

  defp to_map(form) do
    form
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.new(fn {field, value} -> {Atom.to_string(field), value} end)
  end
end
