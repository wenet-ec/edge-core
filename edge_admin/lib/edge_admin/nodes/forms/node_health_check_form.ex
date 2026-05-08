# edge_admin/lib/edge_admin/nodes/forms/node_health_check_form.ex
defmodule EdgeAdmin.Nodes.Forms.NodeHealthCheckForm do
  @moduledoc """
  Form for validating agent node health check reports.

  Agents report their health status (healthy or unhealthy) when using HTTP fallback mode.
  This form validates the status value before updating the node record.
  """
  use EdgeAdmin.Form

  # Agents only report :healthy or :unhealthy. :unreachable is admin-derived
  # (set when health checks fail to reach the node), never agent-reported.
  @agent_reported_statuses [:healthy, :unhealthy]

  embedded_schema do
    field(:status, Ecto.Enum, values: @agent_reported_statuses)
  end

  @doc """
  Validates node health check parameters from agent.

  ## Validations
  - `status` - Must be `"healthy"` or `"unhealthy"` on the wire (cast to atom)

  ## Returns
  - `{:ok, attrs}` - Validated attributes as map (status is an atom)
  - `{:error, changeset}` - Validation errors

  ## Examples

      iex> changeset(%{"status" => "healthy"})
      {:ok, %{"status" => :healthy}}

      iex> changeset(%{"status" => "unreachable"})
      {:error, %Ecto.Changeset{}}
  """
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, form |> Map.take([:status]) |> stringify_keys()}
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

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
