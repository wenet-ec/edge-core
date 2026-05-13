# edge_agent/lib/edge_agent/edge_clusters/health_check.ex
defmodule EdgeAgent.EdgeClusters.HealthCheck do
  @moduledoc """
  Health check reporting for HTTP fallback mode.

  When VPN is unavailable, agents report their health status to admin
  via HTTP fallback to maintain visibility and node tracking.
  """

  alias EdgeAgent.EdgeClusters.AdminClient

  require Logger

  @doc """
  Reports node health to admin via HTTP fallback.

  Determines current health status and sends report to admin.
  Used by `EdgeAgent.LocalScheduler.Tasks.report_health_check/0` when operating in HTTP fallback mode.

  ## Returns
  - `:ok` - Report sent successfully
  - `{:error, reason}` - Report failed
  """
  @spec report() :: :ok | {:error, term()}
  def report do
    status = determine_status()

    Logger.debug("Reporting health check: #{status}")

    result = AdminClient.report_health_check(status)

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

  # Determines current health status by running all health checks
  defp determine_status do
    checks = EdgeAgentHealth.checks()

    # Run all checks and see if any fail
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
