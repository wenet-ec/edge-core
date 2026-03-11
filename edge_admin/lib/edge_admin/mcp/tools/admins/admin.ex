# edge_admin/lib/edge_admin/mcp/tools/admins/admin.ex
defmodule EdgeAdmin.MCP.Tools.Admins.GetAdmin do
  @moduledoc "Get information about this admin instance — ID, version, assigned clusters, and peer count."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin()), frame}
  end
end

defmodule EdgeAdmin.MCP.Tools.Admins.GetAdminCluster do
  @moduledoc "Get the admin cluster status — all peer admin instances, their assigned edge clusters, and degraded flag."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), Metadata.get_admin_cluster()), frame}
  end
end

defmodule EdgeAdmin.MCP.Tools.Admins.ListEdgeClusters do
  @moduledoc "List all edge clusters currently assigned to admin instances."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), %{edge_clusters: Metadata.get_edge_clusters()}), frame}
  end
end

defmodule EdgeAdmin.MCP.Tools.Admins.ListOrphanedClusters do
  @moduledoc "List clusters with no assigned admin instance. These cannot receive commands until an admin picks them up."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Admins.Metadata

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.json(Response.tool(), %{orphaned_clusters: Metadata.get_orphaned_clusters()}), frame}
  end
end

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
