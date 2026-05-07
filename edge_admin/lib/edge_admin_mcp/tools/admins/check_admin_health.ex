# edge_admin/lib/edge_admin_mcp/tools/admins/check_admin_health.ex
defmodule EdgeAdminMcp.Tools.Admins.CheckAdminHealth do
  @moduledoc """
  Run all admin health checks and return pass/fail per component.

  Checks: Database, Membership, Metadata, Netmaker API, Netclient, Proxy
  Servers, Event Broker. Use this to diagnose why nodes can't enroll,
  commands aren't reaching nodes, or the admin is in a degraded state.

  Check names match the labels in `EdgeAdminHealth.checks/0` so the
  response is searchable against the same identifiers operators see in
  `/health` payloads and in logs.

  ## Why the shape differs from `/healthz`

  Both surfaces invoke the same check functions in `EdgeAdminHealth` and run
  them through the same `PlugCheckup.Check.Runner` — checks and runner are
  shared. Only the output shape diverges: `/healthz` returns PlugCheckup's
  JSON (with HTTP status semantics for K8s probes / load balancers); this
  tool flattens to `%{healthy, checks: [%{name, status, reason?}]}` because
  that shape is friendlier for an AI agent to summarise.
  """
  use EdgeAdminMcp, :tool

  # Suppress Dialyzer's false positive on `execute/2`.
  #
  # `PlugCheckup.Check.Runner.async_run/2` declares its return as `tuple()`
  # (unconstrained), but Dialyzer infers a tighter success typing from the
  # implementation that requires `%PlugCheckup.Check{result: atom(),
  # time: pos_integer()}`. Our input has `result: nil, time: nil` (unrun
  # checks — the runner *fills these in*, that's its job), so Dialyzer
  # concludes the call "will never return" even though it works fine at
  # runtime.
  #
  # This is `/healthz`'s code path too — same checks, same runner, same
  # shape — and `/healthz` has been working in production. The runtime is
  # correct; only Dialyzer's static view is overly pessimistic.
  #
  # Future fix path: upstream a tighter `@spec` to PlugCheckup
  # (`{:ok, [Check.t()]} | {:error, [Check.t()]}`) so Dialyzer sees the
  # real contract. PlugCheckup is at v1.0.0 (`voughtdq/plug_checkup`), a
  # cooperative upstream PR is realistic. When that lands and we bump the
  # dep, this suppression becomes obsolete and Dialyzer will tell us via
  # "Unnecessary Skips".
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
