# edge_agent/lib/edge_agent/admin_gateway/health_check.ex
defmodule EdgeAgent.AdminGateway.HealthCheck do
  @moduledoc """
  Health check reporting to the Admin Gateway during HTTP fallback.

  When VPN is unavailable, agents report their health status to the Admin
  Gateway via HTTP fallback to maintain visibility and node tracking.
  """

  alias EdgeAgent.AdminGateway.Client

  require Logger

  @doc """
  Reports node health to the Admin Gateway via HTTP fallback.

  Used by `EdgeAgent.BackgroundJobs.Quantum.Tasks.report_health_check/0`.
  """
  @spec report() :: :ok | {:error, term()}
  def report do
    status = determine_status()

    Logger.debug("Reporting health check: #{status}")

    result = Client.report_health_check(status)

    telemetry_result =
      case result do
        {:ok, _} -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute([:edge_agent, :health_check, :report], %{count: 1}, %{result: telemetry_result})

    case result do
      {:ok, _response} ->
        Logger.debug("Health check reported successfully: #{status}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to report health check: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp determine_status do
    checks = EdgeAgentHealth.checks()

    all_healthy =
      Enum.all?(checks, fn check ->
        case apply(check.module, check.function, []) do
          :ok -> true
          {:error, _reason} -> false
        end
      end)

    if all_healthy do
      "healthy"
    else
      "unhealthy"
    end
  end
end
