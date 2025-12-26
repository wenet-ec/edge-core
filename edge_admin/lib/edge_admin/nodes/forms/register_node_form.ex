# edge_admin/lib/edge_admin/nodes/forms/register_node_form.ex
defmodule EdgeAdmin.Nodes.Forms.RegisterNodeForm do
  @moduledoc """
  Form for validating agent node registration inputs.

  Handles input validation and normalization for node registration (create or update).
  This form validates external API inputs from agents before passing to the domain layer.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:node_id, :string)
    field(:network_name, :string)
    field(:id_type, :string)
    field(:http_port, :integer)
    field(:ssh_port, :integer)
    field(:host_metrics_port, :integer)
    field(:wireguard_metrics_port, :integer)
    field(:http_proxy_port, :integer)
    field(:socks5_proxy_port, :integer)
    field(:version, :string)
    field(:self_update_enabled, :boolean)
  end

  @doc """
  Validates and normalizes agent node registration parameters.

  ## Validations
  - Format validations: UUID, ports, network name format
  - Checks if cluster exists (via get_cluster_fn callback)

  ## Returns
  - `{:ok, attrs}` - Validated attributes as map
  - `{:error, changeset}` - Validation errors
  """
  def changeset(attrs, get_cluster_fn \\ &EdgeAdmin.Nodes.get_cluster/1)

  def changeset(%{"node" => node_attrs}, get_cluster_fn) when is_map(node_attrs) do
    # Unwrap node
    changeset(node_attrs, get_cluster_fn)
  end

  def changeset(attrs, get_cluster_fn) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :node_id,
      :network_name,
      :id_type,
      :http_port,
      :ssh_port,
      :host_metrics_port,
      :wireguard_metrics_port,
      :http_proxy_port,
      :socks5_proxy_port,
      :version,
      :self_update_enabled
    ])
    |> validate_required([
      :node_id,
      :network_name,
      :id_type,
      :http_port,
      :ssh_port,
      :host_metrics_port,
      :wireguard_metrics_port,
      :http_proxy_port,
      :socks5_proxy_port,
      :version,
      :self_update_enabled
    ])
    |> validate_uuid_format(:node_id)
    |> validate_network_name()
    |> validate_cluster_exists(get_cluster_fn)
    |> validate_inclusion(:id_type, ["persistent", "random"])
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

  def changeset(_params, _get_cluster_fn) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:node, "is required")
     |> apply_action!(:insert)}
  end

  defp validate_uuid_format(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID"}]
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

  defp validate_cluster_exists(changeset, get_cluster_fn) do
    network_name = get_field(changeset, :network_name)

    if network_name && changeset.valid? do
      # Parse cluster name from network name (e.g., "cluster-default" -> "default")
      cluster_name = String.replace_prefix(network_name, "cluster-", "")

      case get_cluster_fn.(cluster_name) do
        {:ok, _cluster} -> changeset
        {:error, :not_found} -> add_error(changeset, :network_name, "cluster does not exist")
      end
    else
      changeset
    end
  end

  defp validate_port(changeset, field) do
    changeset
    |> validate_number(field, greater_than: 0, less_than_or_equal_to: 65535)
  end

  @doc """
  Adds a "not found in Netmaker" error to the node_id field.

  Used when the node_id passes format validation but doesn't exist in Netmaker.
  Returns an error changeset that can be returned from context functions.
  """
  def add_netmaker_not_found_error do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:node_id, "node not found in Netmaker network")
     |> apply_action!(:insert)}
  end

  defp to_map(%__MODULE__{} = form) do
    # Convert to map with string keys, removing nil values
    %{
      "node_id" => form.node_id,
      "network_name" => form.network_name,
      "id_type" => form.id_type,
      "http_port" => form.http_port,
      "ssh_port" => form.ssh_port,
      "host_metrics_port" => form.host_metrics_port,
      "wireguard_metrics_port" => form.wireguard_metrics_port,
      "http_proxy_port" => form.http_proxy_port,
      "socks5_proxy_port" => form.socks5_proxy_port,
      "version" => form.version,
      "self_update_enabled" => form.self_update_enabled
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
