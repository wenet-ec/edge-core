# edge_admin/lib/edge_admin/mcp/tools/admins/check_admin_health.ex
defmodule EdgeAdmin.MCP.Tools.Admins.CheckAdminHealth do
  @moduledoc """
  Run all admin health checks and return pass/fail per component.

  Checks: Database, Bootstrap, Metadata, Netmaker API, Netclient VPN, Proxy Servers.
  Use this to diagnose why nodes can't enroll, commands aren't reaching nodes,
  or the admin is in a degraded state.
  """
  use EdgeAdmin.MCP, :tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    results =
      EdgeAdminHealth.checks()
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
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> %{name: "unknown", status: "error", reason: "timeout"}
      end)

    healthy = Enum.all?(results, &(&1.status == "ok"))

    {:reply, Response.json(Response.tool(), %{healthy: healthy, checks: results}), frame}
  end
end
