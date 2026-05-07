# edge_admin/lib/edge_admin/nodes/forms/create_cluster_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateClusterForm do
  @moduledoc """
  Form for validating cluster creation inputs.

  Handles input validation and normalization before passing data to the domain layer.
  This form validates external API inputs, while the Cluster schema validates model integrity.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Naming

  embedded_schema do
    field(:name, :string)
    field(:ipv4_range, :string)
    field(:node_limit, :integer)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :ipv4_range, :node_limit])
    |> validate_name()
    |> validate_ipv4_range()
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

  # "default" is reserved — it's a URL keyword on `/api/v1/clusters/default/...`
  # routes that resolves to whichever cluster `DEFAULT_CLUSTER_NAME` points at.
  # Also enforced in `EdgeAdmin.Nodes.Schemas.Cluster.changeset/2`.
  @reserved_names ~w(default)

  defp validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, max: Naming.cluster_name_max_length())
    |> validate_format(:name, Naming.cluster_name_regex(),
      message: "must be lowercase alphanumeric with hyphens, cannot start/end with hyphen"
    )
    |> validate_exclusion(:name, @reserved_names, message: "is reserved")
  end

  defp validate_ipv4_range(changeset) do
    # Basic CIDR format validation (x.x.x.x/prefix)
    # Deeper validation happens in Cluster schema using Vpn.parse_cidr
    validate_format(changeset, :ipv4_range, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/,
      message: "must be in CIDR format (e.g., 100.64.0.0/24)"
    )
  end

  defp validate_node_limit(changeset) do
    validate_number(changeset, :node_limit, greater_than: 0)
  end

  defp to_map(%__MODULE__{} = form) do
    # Convert to map with string keys, removing nil values
    %{
      "name" => form.name,
      "ipv4_range" => form.ipv4_range,
      "node_limit" => form.node_limit
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
