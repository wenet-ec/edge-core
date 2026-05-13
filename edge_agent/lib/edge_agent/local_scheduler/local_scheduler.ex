# edge_agent/lib/edge_agent/local_scheduler/local_scheduler.ex
defmodule EdgeAgent.LocalScheduler do
  @moduledoc """
  Quantum scheduler for the agent's recurring, in-process, stateless tasks.

  Jobs here run **in-process** with no `oban_jobs` row written. They are
  fire-and-forget on a clock and idempotent — if a tick fails, the next tick
  redoes it. Anything that needs durable lifecycle (claim-once, retry,
  per-execution record) belongs on Oban, not here. See
  `EdgeAgent.Commands.Workers.ExecuteCommandWorker` for the only remaining
  Oban worker.

  The job entry points live in `EdgeAgent.LocalScheduler.Tasks` — that module
  is the only thing this scheduler calls into.
  """

  use Quantum, otp_app: :edge_agent
end
