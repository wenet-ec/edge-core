# edge_admin/lib/edge_admin_mcp/tools/admins/check_admin_health.ex
defmodule EdgeAdminMcp.Tools.Admins.CheckAdminHealth do
  @moduledoc """
  Run all admin health checks and return pass/fail per component.

  Checks: Database, Membership, Metadata, Netmaker API, Netclient VPN, Proxy Servers.
  Use this to diagnose why nodes can't enroll, commands aren't reaching nodes,
  or the admin is in a degraded state.
  """
  use EdgeAdminMcp, :tool

  @impl true
  def title, do: "Check Admin Health"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    checks = EdgeAdminHealth.checks()

    results =
      checks
      |> Task.async_stream(
        fn check ->
          result =
            try do
              apply(check.module, check.function, [])
            rescue
              e -> {:error, Exception.message(e)}
            end

          case result do
            :ok -> %{name: check.name, status: "ok"}
            {:error, reason} -> %{name: check.name, status: "error", reason: reason}
          end
        end,
        timeout: 6_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(checks)
      |> Enum.map(fn
        {{:ok, result}, _check} -> result
        {{:exit, :timeout}, check} -> %{name: check.name, status: "error", reason: "timeout"}
      end)

    healthy = Enum.all?(results, &(&1.status == "ok"))

    {:reply, Response.json(Response.tool(), %{healthy: healthy, checks: results}), frame}
  end
end
