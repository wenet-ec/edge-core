# edge_admin/lib/edge_admin_mcp/tools/admins/check_admin_health.ex
defmodule EdgeAdminMcp.Tools.Admins.CheckAdminHealth do
  @moduledoc """
  Runs the Admin health checks and returns a model-friendly status for each
  component. The result includes an overall `healthy` flag and per-check status
  with a reason when a check fails.
  """
  use EdgeAdminMcp, :tool

  # PlugCheckup's runner spec is too loose (`tuple()`), while Dialyzer infers
  # a stricter internal shape and treats unrun checks (`result/time: nil`) as
  # impossible input. Runtime is correct: this is the same path used by
  # `/healthz`, and the runner fills those fields before returning.
  @dialyzer {:nowarn_function, execute: 2}

  @impl true
  def title, do: "Check Admin Health"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    # Reuse PlugCheckup's runner so this tool and `/healthz` share the same
    # parallel-execution + timeout + rescue/catch semantics. The shapes diverge
    # downstream (model-friendly here, PlugCheckup JSON on the HTTP path).
    {_status, results} = PlugCheckup.Check.Runner.async_run(EdgeAdminHealth.checks(), 6_000)

    formatted = Enum.map(results, &format_check/1)
    healthy = Enum.all?(formatted, &(&1.status == "ok"))

    {:reply, Response.json(Response.tool(), %{healthy: healthy, checks: formatted}), frame}
  end

  defp format_check(%PlugCheckup.Check{name: name, result: :ok}) do
    %{name: name, status: "ok"}
  end

  defp format_check(%PlugCheckup.Check{name: name, result: {:error, reason}}) do
    %{name: name, status: "error", reason: format_reason(reason)}
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(:timeout), do: "timeout"
  defp format_reason(reason), do: inspect(reason)
end
