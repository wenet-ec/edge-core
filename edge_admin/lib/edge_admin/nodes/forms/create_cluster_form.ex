# edge_admin/lib/edge_admin/nodes/forms/create_cluster_form.ex
defmodule EdgeAdmin.Nodes.Forms.CreateClusterForm do
  @moduledoc """
  Form for validating cluster creation inputs.

  Handles input validation and normalization before passing data to the domain layer.
  This form validates external API inputs, while the Cluster schema validates model integrity.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:name, :string)
    field(:ipv4_range, :string)
  end

  def changeset(%{"cluster" => cluster_attrs}) do
    %__MODULE__{}
    |> cast(cluster_attrs, [:name, :ipv4_range])
    |> validate_name()
    |> validate_ipv4_range()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:cluster, "is required")
     |> apply_action!(:insert)}
  end

  defp validate_name(changeset) do
    changeset
    |> validate_length(:name, max: 24)
    |> validate_format(:name, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
         message: "must be lowercase alphanumeric with hyphens, cannot start/end with hyphen")
  end

  defp validate_ipv4_range(changeset) do
    # Basic CIDR format validation (x.x.x.x/prefix)
    # Deeper validation happens in Cluster schema using Vpn.parse_cidr
    changeset
    |> validate_format(:ipv4_range, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/,
         message: "must be in CIDR format (e.g., 100.64.0.0/24)")
  end

  defp to_map(%__MODULE__{} = form) do
    # Convert to map with string keys, removing nil values
    %{
      "name" => form.name,
      "ipv4_range" => form.ipv4_range
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
