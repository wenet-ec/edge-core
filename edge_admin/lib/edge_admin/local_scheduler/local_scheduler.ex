# edge_admin/lib/edge_admin/local_scheduler/local_scheduler.ex
defmodule EdgeAdmin.LocalScheduler do
  @moduledoc """
  Quantum scheduler for local (per-admin) periodic tasks.

  Unlike Oban (which runs jobs on ONE leader node), Quantum runs tasks
  locally on EACH admin node.

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
