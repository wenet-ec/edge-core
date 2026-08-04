# edge_admin/lib/edge_admin/nodes/forms/push_node_diagnostic_form.ex
defmodule EdgeAdmin.Nodes.Forms.PushNodeDiagnosticForm do
  @moduledoc """
  Validates an Agent-pushed diagnostic report.
  """

  use EdgeAdmin.Form

  @check_names ~w(
    wireguard_interface
    netclient
    networks
    configured_peers
    derp_map
    database
    bootstrap
    ssh_server
    metrics_servers
    proxy_servers
  )

  embedded_schema do
    field(:diagnostic, :map)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:diagnostic])
    |> validate_required([:diagnostic])
    |> validate_change(:diagnostic, &validate_diagnostic/2)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, %{"diagnostic" => form.diagnostic}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_attrs) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_diagnostic(:diagnostic, diagnostic) when is_map(diagnostic) do
    required_diagnostic_errors(diagnostic) ++ diagnostic_value_errors(diagnostic)
  end

  defp validate_diagnostic(:diagnostic, _diagnostic), do: [diagnostic: "must be an object"]

  defp required_diagnostic_errors(diagnostic) do
    Enum.flat_map(["collected_at", "overall", "checks"], fn key ->
      if Map.has_key?(diagnostic, key), do: [], else: [diagnostic: "must include #{key}"]
    end)
  end

  defp diagnostic_value_errors(diagnostic) do
    []
    |> validate_collected_at(Map.get(diagnostic, "collected_at"))
    |> validate_overall(Map.get(diagnostic, "overall"))
    |> validate_checks(Map.get(diagnostic, "checks"))
  end

  defp validate_collected_at(errors, value) when is_binary(value) and value != "" do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> errors
      _ -> [{:diagnostic, "collected_at must be an ISO 8601 date-time"} | errors]
    end
  end

  defp validate_collected_at(errors, _value), do: [{:diagnostic, "collected_at must be an ISO 8601 date-time"} | errors]

  defp validate_overall(errors, value) when value in ["pass", "warn", "fail"], do: errors
  defp validate_overall(errors, _value), do: [{:diagnostic, "overall must be pass, warn, or fail"} | errors]

  defp validate_checks(errors, value) when is_list(value) do
    if Enum.all?(value, &valid_check?/1) do
      errors
    else
      [{:diagnostic, "checks must contain valid diagnostic checks"} | errors]
    end
  end

  defp validate_checks(errors, _value), do: [{:diagnostic, "checks must be an array"} | errors]

  defp valid_check?(%{"name" => name, "status" => status, "duration_ms" => duration_ms, "details" => details} = check)
       when name in @check_names and status in ["pass", "warn", "fail"] and is_integer(duration_ms) and duration_ms >= 0 and
              is_map(details) do
    case Map.fetch(check, "summary") do
      :error -> true
      {:ok, summary} -> is_binary(summary)
    end
  end

  defp valid_check?(_check), do: false
end
