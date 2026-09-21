# edge_admin/lib/edge_admin/ingress_tunneling/forms/create_tunnel_connection_form.ex
defmodule EdgeAdmin.IngressTunneling.Forms.CreateTunnelConnectionForm do
  @moduledoc false
  use EdgeAdmin.Form

  embedded_schema do
    field(:node_id, :string)
  end

  @spec changeset(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:node_id])
    |> validate_required([:node_id])
    |> validate_uuid(:node_id)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, %{"node_id" => form.node_id}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_attrs) do
    changeset = %__MODULE__{} |> cast(%{}, []) |> add_error(:base, "invalid parameters - expected a map")
    {:error, %{changeset | action: :insert}}
  end

  defp validate_uuid(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID format"}]
      end
    end)
  end
end
