# edge_admin/lib/edge_admin/background_jobs/quantum/quantum.ex
defmodule EdgeAdmin.BackgroundJobs.Quantum do
  @moduledoc """
  Quantum scheduler for tasks running on each Admin instance.

  Quantum runs tasks locally on each admin node. Jobs that should avoid
  duplicate cluster-wide work use their own weak-leader guard; jobs that need
  DB-backed coordination belong in Oban.

  Quantum job telemetry is consumed by `EdgeAdminWeb.Telemetry` for monitoring
  and Phoenix LiveDashboard.
  """

  use Quantum, otp_app: :edge_admin
end
