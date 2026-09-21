# edge_admin/lib/edge_admin/ingress_tunneling/forms/create_tunnel_client_form.ex
defmodule EdgeAdmin.IngressTunneling.Forms.CreateTunnelClientForm do
  @moduledoc "Validates Tunnel Client creation and optional connection targets."
  use EdgeAdmin.Form

  embedded_schema do
    field(:node_ids, {:array, :string}, default: [])
  end

  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:node_ids])
    |> validate_node_ids()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, %{"node_ids" => form.node_ids || []}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_attrs) do
    changeset = %__MODULE__{} |> cast(%{}, []) |> add_error(:base, "invalid parameters - expected a map")
    {:error, %{changeset | action: :insert}}
  end

  defp validate_node_ids(changeset) do
    validate_change(changeset, :node_ids, fn :node_ids, node_ids ->
      cond do
        not is_list(node_ids) ->
          [node_ids: "must be an array"]

        Enum.uniq(node_ids) != node_ids ->
          [node_ids: "must not contain duplicates"]

        Enum.any?(node_ids, fn node_id -> Ecto.UUID.cast(node_id) == :error end) ->
          [node_ids: "must contain valid UUIDs"]

        true ->
          []
      end
    end)
  end
end
