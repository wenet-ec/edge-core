# edge_admin/lib/edge_admin/nodes/forms/create_cluster_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateClusterForm do
  @moduledoc """
  Form for validating cluster creation inputs.

  Handles input validation and normalization before passing data to the domain layer.
  This form validates external API inputs, while the Cluster schema validates model integrity.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Nodes.Validators.ClusterValidators

  embedded_schema do
    field(:name, :string)
    field(:ipv4_range, :string)
    field(:ipv6_range, :string)
    field(:node_limit, :integer)
  end

  @doc "Validates and normalizes cluster creation attributes."
  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :ipv4_range, :ipv6_range, :node_limit])
    |> validate_required([:name])
    |> validate_name()
    |> validate_ipv4_range()
    |> validate_ipv6_range()
    |> validate_node_limit()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_name(changeset) do
    validate_change(changeset, :name, fn :name, value ->
      case ClusterValidators.name_error(value) do
        :ok -> []
        {:error, message} -> [name: message]
      end
    end)
  end

  defp validate_ipv4_range(changeset) do
    validate_change(changeset, :ipv4_range, fn :ipv4_range, value ->
      if ClusterValidators.valid_ipv4_cidr_format?(value),
        do: [],
        else: [ipv4_range: "must be in CIDR format (e.g., 100.64.0.0/24)"]
    end)
  end

  defp validate_ipv6_range(changeset) do
    validate_change(changeset, :ipv6_range, fn :ipv6_range, value ->
      if ClusterValidators.valid_ipv6_cidr_format?(value),
        do: [],
        else: [ipv6_range: "must be an IPv6 CIDR (e.g., fd7a:91c2:4e8b::/64)"]
    end)
  end

  defp validate_node_limit(changeset) do
    validate_change(changeset, :node_limit, fn :node_limit, value ->
      if ClusterValidators.valid_node_limit?(value), do: [], else: [node_limit: "must be greater than 0"]
    end)
  end

  defp to_map(%__MODULE__{} = form) do
    # Convert to map with string keys, removing nil values
    %{
      "name" => form.name,
      "ipv4_range" => form.ipv4_range,
      "ipv6_range" => form.ipv6_range,
      "node_limit" => form.node_limit
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
