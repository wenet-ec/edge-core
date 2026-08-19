# edge_admin/lib/edge_admin/background_jobs/quantum.ex
defmodule EdgeAdmin.BackgroundJobs.Quantum do
  @moduledoc """
  Quantum scheduler for tasks running on each Admin instance.

  Quantum runs tasks locally on each admin node. Jobs that should avoid
  duplicate cluster-wide work use their own weak-leader guard; jobs that need
  DB-backed coordination belong in Oban.

  ## Telemetry Events

  Quantum automatically emits the following telemetry events for monitoring:

  - `[:quantum, :job, :start]` - Emitted when a job execution starts
    - Measurement: `%{system_time: integer()}`
    - Metadata: `%{job: Quantum.Job.t(), node: node(), scheduler: atom()}`

  - `[:quantum, :job, :stop]` - Emitted when a job execution completes successfully
    - Measurement: `%{duration: integer()}` (native time)
    - Metadata: `%{job: Quantum.Job.t(), node: node(), scheduler: atom(), result: term()}`

  - `[:quantum, :job, :exception]` - Emitted when a job execution fails
    - Measurement: `%{duration: integer()}` (native time)
    - Metadata: `%{job: Quantum.Job.t(), node: node(), scheduler: atom(), kind: atom(), reason: term(), stacktrace: list()}`

  These events are consumed by `EdgeAdminWeb.Telemetry` and displayed in Phoenix LiveDashboard.
  See `EdgeAdminWeb.Telemetry.metrics/0` for the full list of metrics.
  """

  use Quantum, otp_app: :edge_admin
end
