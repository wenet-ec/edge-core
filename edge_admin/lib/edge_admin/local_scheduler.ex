# edge_admin/lib/edge_admin/local_scheduler.ex
defmodule EdgeAdmin.LocalScheduler do
  @moduledoc """
  Quantum scheduler for local (per-admin) periodic tasks.

  Unlike Oban (which runs jobs on ONE leader node), Quantum runs tasks
  locally on EACH admin node.
  """

  use Quantum, otp_app: :edge_admin
end
