# edge_agent/lib/edge_agent/background_jobs/quantum/quantum.ex
defmodule EdgeAgent.BackgroundJobs.Quantum do
  @moduledoc """
  Quantum scheduler for the Agent's recurring, in-process tasks.

  Quantum jobs are fire-and-forget and do not create an Oban job record. They
  are expected to be safe to repeat after a failed tick. Work that requires a
  durable lifecycle, retries, or per-execution state belongs on Oban.

  The scheduler calls only `EdgeAgent.BackgroundJobs.Quantum.Tasks`.
  """

  use Quantum, otp_app: :edge_agent
end
