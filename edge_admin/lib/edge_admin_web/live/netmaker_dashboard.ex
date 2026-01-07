defmodule EdgeAdminWeb.NetmakerDashboard do
  @moduledoc """
  LiveDashboard page for monitoring Netmaker API integration health.

  Displays real-time metrics for HTTP requests made to Netmaker API via Finch/Req.

  ## Metrics Displayed

  - Request success/failure rates
  - Average response times
  - Recent errors with details
  - Connection pool statistics
  - API endpoint breakdown

  ## Telemetry Events

  This dashboard consumes Finch telemetry events emitted by Req library:
  - `[:finch, :request, :start]`
  - `[:finch, :request, :stop]`
  - `[:finch, :request, :exception]`
  - `[:finch, :connect, :stop]`
  - `[:finch, :reused_connection]`

  Events are collected in ETS by `EdgeAdminWeb.NetmakerDashboard.Collector`.
  """

  use Phoenix.LiveDashboard.PageBuilder

  @impl true
  def menu_link(_, _) do
    {:ok, "Netmaker"}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    stats = EdgeAdminWeb.NetmakerDashboard.Collector.get_stats()
    assigns = assign(assigns, stats: stats, now: DateTime.utc_now())

    ~H"""
    <h5 class="mb-3">Netmaker API Integration</h5>

    <!-- Overview Cards -->
    <div class="row mb-4">
      <div class="col-md-3">
        <div class="card">
          <div class="card-body">
            <h6 class="card-subtitle mb-2 text-muted">Total Requests</h6>
            <h3 class="card-title"><%= @stats.total_requests %></h3>
          </div>
        </div>
      </div>

      <div class="col-md-3">
        <div class="card">
          <div class="card-body">
            <h6 class="card-subtitle mb-2 text-muted">Success Rate</h6>
            <h3 class="card-title"><%= success_rate(@stats) %>%</h3>
          </div>
        </div>
      </div>

      <div class="col-md-3">
        <div class="card">
          <div class="card-body">
            <h6 class="card-subtitle mb-2 text-muted">Avg Response Time</h6>
            <h3 class="card-title"><%= format_duration(@stats.avg_duration) %></h3>
          </div>
        </div>
      </div>

      <div class="col-md-3">
        <div class="card">
          <div class="card-body">
            <h6 class="card-subtitle mb-2 text-muted">Connections Reused</h6>
            <h3 class="card-title"><%= @stats.connections_reused %></h3>
          </div>
        </div>
      </div>
    </div>

    <!-- Recent Errors -->
    <div class="row mb-4">
      <div class="col-12">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">Recent Errors (Last 20)</h6>
          </div>
          <div class="card-body">
            <%= if Enum.empty?(@stats.recent_errors) do %>
              <p class="text-muted">No errors recorded</p>
            <% else %>
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Timestamp</th>
                    <th>Kind</th>
                    <th>Reason</th>
                    <th>Duration</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for error <- @stats.recent_errors do %>
                    <tr>
                      <td><%= format_timestamp(error.timestamp, @now) %></td>
                      <td><%= error.kind %></td>
                      <td><%= truncate(inspect(error.reason), 80) %></td>
                      <td><%= format_duration(error.duration) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Request Stats -->
    <div class="row">
      <div class="col-12">
        <div class="card">
          <div class="card-header">
            <h6 class="mb-0">Request Statistics (Last Hour)</h6>
          </div>
          <div class="card-body">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Metric</th>
                  <th>Value</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Successful Requests</td>
                  <td><%= @stats.successful_requests %></td>
                </tr>
                <tr>
                  <td>Failed Requests</td>
                  <td><%= @stats.failed_requests %></td>
                </tr>
                <tr>
                  <td>Min Response Time</td>
                  <td><%= format_duration(@stats.min_duration) %></td>
                </tr>
                <tr>
                  <td>Max Response Time</td>
                  <td><%= format_duration(@stats.max_duration) %></td>
                </tr>
                <tr>
                  <td>P95 Response Time</td>
                  <td><%= format_duration(@stats.p95_duration) %></td>
                </tr>
                <tr>
                  <td>New Connections</td>
                  <td><%= @stats.new_connections %></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, socket}
  end

  # Helper functions

  defp success_rate(%{total_requests: 0}), do: "0.0"

  defp success_rate(%{successful_requests: success, total_requests: total}) do
    Float.round(success / total * 100, 1)
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(0), do: "0ms"

  defp format_duration(duration_ns) when is_integer(duration_ns) do
    duration_ms = System.convert_time_unit(duration_ns, :native, :millisecond)

    cond do
      duration_ms < 1 -> "< 1ms"
      duration_ms < 1000 -> "#{duration_ms}ms"
      true -> "#{Float.round(duration_ms / 1000, 2)}s"
    end
  end

  defp format_timestamp(timestamp, now) do
    diff_seconds = DateTime.diff(now, timestamp, :second)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      true -> "#{div(diff_seconds, 3600)}h ago"
    end
  end

  defp truncate(string, max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length) <> "..."
    else
      string
    end
  end
end
