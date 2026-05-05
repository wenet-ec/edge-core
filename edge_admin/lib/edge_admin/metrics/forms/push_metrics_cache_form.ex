# edge_admin/lib/edge_admin/metrics/forms/push_metrics_cache_form.ex
defmodule EdgeAdmin.Metrics.Forms.PushMetricsCacheForm do
  @moduledoc """
  Form for validating agent metrics cache push requests.

  Agents push metrics to admin when using HTTP fallback mode (VPN unavailable).
  This form validates the metrics type and text before storing in cache.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:metrics_type, :string)
    field(:metrics_text, :string)
  end

  @doc """
  Validates metrics cache push parameters from agent.

  ## Validations
  - `metrics_type` - Must be "host", "agent", or "wireguard"
  - `metrics_text` - Required, non-empty string (raw Prometheus text)

  ## Returns
  - `{:ok, attrs}` - Validated attributes as map
  - `{:error, changeset}` - Validation errors

  ## Examples

      iex> changeset(%{"metrics" => %{"metrics_type" => "host", "metrics_text" => "# HELP..."}})
      {:ok, %{"metrics_type" => "host", "metrics_text" => "# HELP..."}}

      iex> changeset(%{"metrics" => %{"metrics_type" => "invalid", "metrics_text" => "..."}})
      {:error, %Ecto.Changeset{}}
  """
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:metrics_type, :metrics_text])
    |> validate_required([:metrics_type, :metrics_text])
    |> validate_inclusion(:metrics_type, ["host", "agent", "wireguard"],
      message: "must be 'host', 'agent', or 'wireguard'"
    )
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, form |> Map.take([:metrics_type, :metrics_text]) |> stringify_keys()}
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
