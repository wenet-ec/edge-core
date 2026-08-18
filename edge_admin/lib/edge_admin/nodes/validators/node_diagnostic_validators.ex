# edge_admin/lib/edge_admin/nodes/validators/node_diagnostic_validators.ex
defmodule EdgeAdmin.Nodes.Validators.NodeDiagnosticValidators do
  @moduledoc "Pure validators for Agent-pushed diagnostic reports."

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

  @spec errors(term()) :: [String.t()]
  def errors(diagnostic) when is_map(diagnostic) do
    required_errors(diagnostic) ++ value_errors(diagnostic)
  end

  def errors(_diagnostic), do: ["must be an object"]

  defp required_errors(diagnostic) do
    Enum.flat_map(["collected_at", "overall", "checks"], fn key ->
      if Map.has_key?(diagnostic, key), do: [], else: ["must include #{key}"]
    end)
  end

  defp value_errors(diagnostic) do
    []
    |> collected_at_error(Map.get(diagnostic, "collected_at"))
    |> overall_error(Map.get(diagnostic, "overall"))
    |> checks_error(Map.get(diagnostic, "checks"))
  end

  defp collected_at_error(errors, value) when is_binary(value) and value != "" do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> errors
      _ -> ["collected_at must be an ISO 8601 date-time" | errors]
    end
  end

  defp collected_at_error(errors, _value), do: ["collected_at must be an ISO 8601 date-time" | errors]

  defp overall_error(errors, value) when value in ["pass", "warn", "fail"], do: errors
  defp overall_error(errors, _value), do: ["overall must be pass, warn, or fail" | errors]

  defp checks_error(errors, value) when is_list(value) do
    if Enum.all?(value, &valid_check?/1), do: errors, else: ["checks must contain valid diagnostic checks" | errors]
  end

  defp checks_error(errors, _value), do: ["checks must be an array" | errors]

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
