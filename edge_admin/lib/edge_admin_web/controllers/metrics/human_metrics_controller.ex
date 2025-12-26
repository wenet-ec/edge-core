# edge_admin/lib/edge_admin_web/controllers/metrics/human_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HumanMetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Metrics.HostMetrics
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Metrics.HumanMetricsSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  tags(["Metrics.Human"])

  operation(:show_unified,
    summary: "Get unified metrics for a node",
    description: """
    Returns aggregated metrics from all available sources for a node:
    - Host metrics (Node Exporter): CPU, memory, disk, uptime
    - Application metrics (agent PromEx): Coming soon

    Provides a complete view of node health and performance in a single request.
    Uses best-effort fetching - if one source fails, others are still returned.
    """,
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Unified metrics retrieved successfully", "application/json", HumanMetricsSchemas.UnifiedMetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }
  )

  @doc """
  Returns unified metrics from all sources (host, application, etc.).

  Fetches metrics in parallel from all available sources and aggregates them.
  Uses best-effort approach - partial failures don't fail the entire request.
  """
  def show_unified(conn, %{"node_id" => node_id}) do
    # Fetch all metrics in parallel
    tasks = [
      Task.async(fn -> HostMetrics.get(node_id) end)
      # Future: Task.async(fn -> ApplicationMetrics.get(node_id) end)
    ]

    results = Task.await_many(tasks, 5_000)

    # Extract host metrics
    host_data = case Enum.at(results, 0) do
      {:ok, metrics} ->
        Map.from_struct(metrics)
        |> Map.put(:available, true)
      {:error, _} ->
        %{available: false, error: "unavailable"}
    end

    unified_metrics = %{
      node_id: node_id,
      timestamp: DateTime.utc_now(),
      cluster_name: host_data[:cluster_name],
      host: host_data
      # Future: application: application_data
    }

    render(conn, :show_unified, metrics: unified_metrics)
  end

  operation(:show_host,
    summary: "Get host metrics for a node",
    description: """
    Returns host-level system metrics from Node Exporter:
    - CPU: cores, load averages
    - Memory: usage, total/available/used in bytes and GB
    - Disk: usage, total/available/used for root filesystem
    - Uptime: seconds and human-readable format
    """,
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Host metrics retrieved successfully", "application/json", HumanMetricsSchemas.HostMetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }
  )

  @doc """
  Returns host-level metrics only (Node Exporter).
  """
  def show_host(conn, %{"node_id" => node_id}) do
    with {:ok, metrics} <- HostMetrics.get(node_id) do
      render(conn, :show_host, metrics: metrics)
    end
  end
end
