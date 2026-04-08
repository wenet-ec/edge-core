# edge_admin/lib/edge_admin/nodes/forms/node_health_check_form.ex
defmodule EdgeAdmin.Nodes.Forms.NodeHealthCheckForm do
  @moduledoc """
  Form for validating agent node health check reports.

  Agents report their health status (healthy or unhealthy) when using HTTP fallback mode.
  This form validates the status value before updating the node record.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:status, :string)
  end

  @doc """
  Validates node health check parameters from agent.

  ## Validations
  - `status` - Must be "healthy" or "unhealthy"

  ## Returns
  - `{:ok, attrs}` - Validated attributes as map
  - `{:error, changeset}` - Validation errors

  ## Examples

      iex> changeset(%{"status" => "healthy"})
      {:ok, %{"status" => "healthy"}}

      iex> changeset(%{"status" => "unreachable"})
      {:error, %Ecto.Changeset{}}
  """
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["healthy", "unhealthy"], message: "must be either 'healthy' or 'unhealthy'")
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, form |> Map.take([:status]) |> stringify_keys()}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:base, "invalid parameters - expected a map")
     |> apply_action!(:insert)}
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
