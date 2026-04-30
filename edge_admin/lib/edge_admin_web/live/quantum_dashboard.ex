# edge_admin/lib/edge_admin_web/live/quantum_dashboard.ex
defmodule EdgeAdminWeb.Live.QuantumDashboard do
  @moduledoc """
  LiveDashboard page for `EdgeAdmin.LocalScheduler` Quantum jobs.

  Shows each configured cron job with its schedule, state, last/next firing,
  and recent outcome. Supports run-now / pause / resume actions per job.

  Reads route through `:erpc.call/4` to the node selected in the LiveDashboard
  node switcher; mutations also dispatch to that node so each admin's
  scheduler can be inspected and controlled independently. Quantum runs on
  every admin (unlike Oban), so each admin has its own LocalScheduler that
  fires independently.

  Run history is recorded by `EdgeAdmin.LocalScheduler.History`, an ETS-backed
  GenServer that listens to Quantum telemetry and keeps one row per job
  (last firing only). Aggregate counters live in PromEx → Grafana.
  """

  use Phoenix.LiveDashboard.PageBuilder

  @rpc_timeout 5_000

  @impl true
  def menu_link(_, _) do
    {:ok, "Quantum"}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, flash_message: nil)}
  end

  @impl true
  def render(assigns) do
    case fetch_snapshot(assigns.page.node) do
      {:ok, jobs} ->
        assigns = assign(assigns, jobs: jobs, error: nil)
        render_page(assigns)

      {:error, reason} ->
        assigns = assign(assigns, error: reason, viewing_node: assigns.page.node)
        render_error(assigns)
    end
  end

  defp render_error(assigns) do
    ~H"""
    <div class="alert alert-danger" role="alert">
      <strong>Failed to read Quantum jobs from {@viewing_node}:</strong>
      <code>{inspect(@error)}</code>
    </div>
    """
  end

  defp render_page(assigns) do
    ~H"""
    <div class="quantum-page">
      <style>
        .quantum-page .text-mono {
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          font-size: 0.875em;
        }
        .quantum-page .badge {
          font-weight: 600;
          padding: 0.35em 0.6em;
        }
        .quantum-page .badge.outcome-ok {
          background-color: #DCFCE7;
          color: #166534;
        }
        .quantum-page .badge.outcome-error {
          background-color: #FEE2E2;
          color: #991B1B;
        }
        .quantum-page .badge.state-active {
          background-color: #DCFCE7;
          color: #166534;
        }
        .quantum-page .badge.state-inactive {
          background-color: #F1F5F9;
          color: #475569;
        }
        .quantum-page .badge.failures {
          background-color: #FEE2E2;
          color: #991B1B;
        }
        .quantum-page .next-run-soon {
          color: #166534;
          font-weight: 500;
        }
        .quantum-page .next-run-error {
          color: #991B1B;
          font-style: italic;
        }
        .quantum-page .last-error {
          color: #991B1B;
          font-size: 0.8em;
        }
        .quantum-page .quantum-actions {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }
        .quantum-page .quantum-actions button {
          padding: 0.25rem 0.6rem;
          font-size: 0.8em;
          font-weight: 600;
          border-radius: 4px;
          border: none;
          color: #FFFFFF;
          cursor: pointer;
          white-space: nowrap;
          transition: background-color 0.15s, transform 0.05s;
        }
        .quantum-page .quantum-actions button:active {
          transform: translateY(1px);
        }
        .quantum-page .quantum-actions .btn-run {
          background-color: #16A34A;
        }
        .quantum-page .quantum-actions .btn-run:hover {
          background-color: #15803D;
        }
        .quantum-page .quantum-actions .btn-pause {
          background-color: #DC2626;
        }
        .quantum-page .quantum-actions .btn-pause:hover {
          background-color: #B91C1C;
        }
        .quantum-page .quantum-actions .btn-resume {
          background-color: #0891B2;
        }
        .quantum-page .quantum-actions .btn-resume:hover {
          background-color: #0E7490;
        }
        .quantum-page .toolbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 1rem;
          margin-bottom: 1rem;
        }
        .quantum-page .tz-toggle {
          display: inline-flex;
          padding: 2px;
          background-color: #F1F5F9;
          border-radius: 6px;
          border: 1px solid #E2E8F0;
        }
        .quantum-page .tz-toggle button {
          padding: 0.3rem 0.9rem;
          font-size: 0.8em;
          font-weight: 600;
          color: #64748B;
          background: transparent;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          transition: background-color 0.15s, color 0.15s;
        }
        .quantum-page .tz-toggle button:hover {
          color: #1E293B;
        }
        .quantum-page .tz-toggle button.active {
          background-color: #FFFFFF;
          color: #155E75;
          box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08);
        }
      </style>

      <div class="toolbar">
        <h5 class="mb-0">Quantum ({length(@jobs)})</h5>

        <div class="tz-toggle" role="group" aria-label="Timezone" id="quantum-tz-toggle">
          <button type="button" data-tz="UTC" class="active">UTC</button>
          <button type="button" data-tz="local">Local</button>
        </div>
      </div>

      <%= if @flash_message do %>
        <div class={"alert alert-#{elem(@flash_message, 0)} py-2 mb-3"}>
          {elem(@flash_message, 1)}
        </div>
      <% end %>

      <div class="card mb-4">
        <div class="card-body">
          <%= if @jobs == [] do %>
            <p class="text-muted mb-0">No Quantum jobs configured.</p>
          <% else %>
            <table class="table table-sm mb-0 align-middle">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>State</th>
                  <th>Schedule</th>
                  <th>Last Run</th>
                  <th>Last Outcome</th>
                  <th>Next Run</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for job <- @jobs do %>
                  <tr>
                    <td>{job.name}</td>
                    <td>
                      <%= case job.state do %>
                        <% :active -> %>
                          <span class="badge state-active">active</span>
                        <% _ -> %>
                          <span class="badge state-inactive">paused</span>
                      <% end %>
                    </td>
                    <td><span class="text-mono">{job.schedule}</span></td>
                    <td>{render_last_run(assigns, job)}</td>
                    <td>{render_last_outcome(assigns, job)}</td>
                    <td class={next_run_class(job)}>{render_next_run(assigns, job)}</td>
                    <td>
                      <div class="quantum-actions">
                        <button
                          type="button"
                          class="btn-run"
                          phx-click="run_now"
                          phx-value-job={job.name}
                          title="Fire this job immediately"
                        >Run now</button>
                        <%= if job.state == :active do %>
                          <button
                            type="button"
                            class="btn-pause"
                            phx-click="pause"
                            phx-value-job={job.name}
                            title="Stop scheduled firing until resumed"
                          >Pause</button>
                        <% else %>
                          <button
                            type="button"
                            class="btn-resume"
                            phx-click="resume"
                            phx-value-job={job.name}
                            title="Re-enable scheduled firing"
                          >Resume</button>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <p class="text-muted small mb-0">
        History persists per-admin while the admin is up; it resets on restart.
        Aggregate execution counts are exported to Prometheus.
      </p>
    </div>
    """
  end

  defp render_last_outcome(assigns, job) do
    assigns = assign(assigns, :job, job)

    ~H"""
    <%= cond do %>
      <% is_nil(@job.last_run_at) -> %>
        <span class="text-muted">never</span>
      <% @job.last_outcome == :ok -> %>
        <span class="badge outcome-ok">ok · {format_duration(@job.last_duration_native)}</span>
      <% @job.last_outcome == :error -> %>
        <div>
          <span class="badge outcome-error">error · {format_duration(@job.last_duration_native)}</span>
          <%= if @job.consecutive_failures > 1 do %>
            <span class="badge failures ms-1">×{@job.consecutive_failures}</span>
          <% end %>
        </div>
        <div class="last-error text-mono">{@job.last_error}</div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Events — node-aware, dispatched via :erpc to the selected node
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("run_now", %{"job" => name}, socket) do
    invoke_action(socket, name, :run_job, "Triggered #{name}")
  end

  def handle_event("pause", %{"job" => name}, socket) do
    invoke_action(socket, name, :deactivate_job, "Paused #{name}")
  end

  def handle_event("resume", %{"job" => name}, socket) do
    invoke_action(socket, name, :activate_job, "Resumed #{name}")
  end

  defp invoke_action(socket, name, action, success_message) do
    job_atom = String.to_existing_atom(name)
    node = socket.assigns.page.node

    case :erpc.call(node, __MODULE__, :remote_action, [action, job_atom], @rpc_timeout) do
      :ok ->
        {:noreply, assign(socket, flash_message: {"success", success_message})}

      {:error, reason} ->
        {:noreply, assign(socket, flash_message: {"danger", "Failed: #{inspect(reason)}"})}
    end
  rescue
    ArgumentError ->
      {:noreply, assign(socket, flash_message: {"danger", "Unknown job: #{name}"})}
  catch
    kind, reason ->
      {:noreply, assign(socket, flash_message: {"danger", "#{kind}: #{inspect(reason)}"})}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # RPC fan-out — reads jobs + history from the selected node
  # ---------------------------------------------------------------------------

  defp fetch_snapshot(node) do
    case :erpc.call(node, __MODULE__, :remote_snapshot, [], @rpc_timeout) do
      {:ok, _jobs} = ok -> ok
      {:error, _reason} = err -> err
      other -> {:error, "unexpected remote_snapshot result: #{inspect(other)}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  @doc false
  # Called via :erpc on the selected node. Reads from LocalScheduler + History.
  def remote_snapshot do
    history = EdgeAdmin.LocalScheduler.History.all()
    now = DateTime.utc_now()

    jobs =
      EdgeAdmin.LocalScheduler.jobs()
      |> Enum.map(fn {_name, job} -> serialise_job(job, history, now) end)
      |> Enum.sort_by(& &1.name)

    {:ok, jobs}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc false
  # Mutating action dispatched via :erpc.
  def remote_action(action, name) when action in [:run_job, :activate_job, :deactivate_job] do
    apply(EdgeAdmin.LocalScheduler, action, [name])
    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp serialise_job(job, history, now) do
    history_entry = Map.get(history, job.name)

    %{
      name: to_string(job.name),
      atom_name: job.name,
      state: job.state,
      schedule: format_schedule(job.schedule),
      schedule_expr: job.schedule,
      timezone: job.timezone,
      task: format_task(job.task),
      next_run_naive: compute_next_run(job, now),
      last_run_at: history_entry && history_entry.last_run_at,
      last_duration_native: history_entry && history_entry.last_duration_native,
      last_outcome: history_entry && history_entry.last_outcome,
      last_error: history_entry && history_entry.last_error,
      consecutive_failures: (history_entry && history_entry.consecutive_failures) || 0
    }
  end

  defp compute_next_run(%{state: :inactive}, _now), do: nil

  defp compute_next_run(%{schedule: %Crontab.CronExpression{} = expr, timezone: tz}, now) do
    naive_now = naive_now_in_tz(now, tz)

    case Crontab.Scheduler.get_next_run_date(expr, naive_now) do
      {:ok, naive_dt} -> {:ok, naive_dt, tz}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp compute_next_run(_job, _now), do: nil

  defp naive_now_in_tz(now, :utc), do: DateTime.to_naive(now)

  defp naive_now_in_tz(now, tz) when is_binary(tz) do
    case DateTime.shift_zone(now, tz) do
      {:ok, dt} -> DateTime.to_naive(dt)
      _ -> DateTime.to_naive(now)
    end
  end

  defp naive_now_in_tz(now, _), do: DateTime.to_naive(now)

  # ---------------------------------------------------------------------------
  # Formatters (page-side, run on the calling node)
  # ---------------------------------------------------------------------------

  defp format_schedule(%Crontab.CronExpression{} = expr), do: Crontab.CronExpression.Composer.compose(expr)
  defp format_schedule(other), do: inspect(other)

  defp format_task({m, f, a}), do: "#{inspect(m)}.#{f}/#{length(a)}"
  defp format_task(fun) when is_function(fun), do: inspect(fun)
  defp format_task(other), do: inspect(other)

  defp format_duration(nil), do: "?"

  defp format_duration(native_units) when is_integer(native_units) do
    ms = System.convert_time_unit(native_units, :native, :millisecond)

    cond do
      ms < 1 -> "<1ms"
      ms < 1000 -> "#{ms}ms"
      true -> "#{Float.round(ms / 1000, 2)}s"
    end
  end

  # Renders the "Last Run" cell. The <time> element carries the ISO UTC
  # timestamp; client-side JS swaps the text on tz toggle.
  defp render_last_run(assigns, job) do
    assigns = assign(assigns, :job, job)

    ~H"""
    <%= cond do %>
      <% is_nil(@job.last_run_at) -> %>
        <span class="text-muted">never</span>
      <% true -> %>
        <time class="qt-time" datetime={DateTime.to_iso8601(@job.last_run_at)}>
          {@job.last_run_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()}
        </time>
        <span class="text-muted">({humanize_ago(DateTime.diff(DateTime.utc_now(), @job.last_run_at, :second))})</span>
    <% end %>
    """
  end

  defp render_next_run(assigns, job) do
    assigns = assign(assigns, :next_run, next_run_payload(job))

    ~H"""
    <%= case @next_run do %>
      <% :dash -> %>
        —
      <% {:error, reason} -> %>
        error: {reason}
      <% {:ok, %{iso: iso, naive: naive, rel: rel}} -> %>
        <time class="qt-time" datetime={iso}>{naive}</time>
        <span class="text-muted">({rel})</span>
    <% end %>
    """
  end

  # Pure data — no HEEx pattern-matching inside cond branches (which leak).
  defp next_run_payload(%{state: :inactive}), do: :dash
  defp next_run_payload(%{next_run_naive: nil}), do: :dash
  defp next_run_payload(%{next_run_naive: {:error, reason}}), do: {:error, reason}

  defp next_run_payload(%{next_run_naive: {:ok, naive_dt, job_tz}}) do
    {:ok, dt} = DateTime.from_naive(naive_dt, "Etc/UTC")
    naive_now = naive_now_in_tz(DateTime.utc_now(), job_tz)
    seconds_until = NaiveDateTime.diff(naive_dt, naive_now, :second)

    {:ok,
     %{
       iso: DateTime.to_iso8601(dt),
       naive: NaiveDateTime.to_string(NaiveDateTime.truncate(naive_dt, :second)),
       rel: humanize_in(seconds_until)
     }}
  rescue
    e -> {:error, "next_run_payload: #{Exception.message(e)}"}
  end

  # Catch-all: any unexpected shape becomes a visible error rather than a render crash.
  defp next_run_payload(other), do: {:error, "unexpected next_run shape: #{inspect(other)}"}

  defp humanize_ago(seconds) when seconds < 0, do: "in the future"
  defp humanize_ago(seconds) when seconds < 60, do: "#{seconds}s ago"
  defp humanize_ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m ago"
  defp humanize_ago(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)}h ago"
  defp humanize_ago(seconds), do: "#{div(seconds, 86_400)}d ago"

  defp humanize_in(seconds) when seconds <= 0, do: "now"
  defp humanize_in(seconds) when seconds < 60, do: "in #{seconds}s"
  defp humanize_in(seconds) when seconds < 3600, do: "in #{div(seconds, 60)}m"
  defp humanize_in(seconds) when seconds < 86_400, do: "in #{div(seconds, 3600)}h"
  defp humanize_in(seconds), do: "in #{div(seconds, 86_400)}d"

  defp next_run_class(%{state: :inactive}), do: "text-muted"
  defp next_run_class(%{next_run_naive: nil}), do: "text-muted"
  defp next_run_class(%{next_run_naive: {:error, _}}), do: "next-run-error"

  defp next_run_class(%{next_run_naive: {:ok, naive_dt, job_tz}}) do
    now = DateTime.utc_now()
    naive_now = naive_now_in_tz(now, job_tz)
    seconds = NaiveDateTime.diff(naive_dt, naive_now, :second)
    if seconds <= 60 * 30, do: "next-run-soon", else: ""
  end
end
