# edge_agent/test/edge_agent/commands/workers/execute_command_worker_test.exs
defmodule EdgeAgent.Commands.Workers.ExecuteCommandWorkerTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands.Workers.ExecuteCommandWorker

  # ---------------------------------------------------------------------------
  # expired?/1 — decides whether to skip execution. The boundary semantics
  # (equality counts as expired) match the Commands.expire_stale_executions
  # convention on the admin side.
  # ---------------------------------------------------------------------------

  describe "expired?/1" do
    test "nil expires_at → not expired (no deadline configured)" do
      refute ExecuteCommandWorker.expired?(%{expires_at: nil})
    end

    test "future expires_at → not expired" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      refute ExecuteCommandWorker.expired?(%{expires_at: future})
    end

    test "past expires_at → expired" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert ExecuteCommandWorker.expired?(%{expires_at: past})
    end

    test "equality with now counts as expired (compare returns :eq, not :gt)" do
      # A second-truncated 'now' is at best equal to the comparison's now,
      # never strictly after — so this lands on the :eq branch which is
      # treated as expired.
      now = DateTime.truncate(DateTime.utc_now(), :second)
      assert ExecuteCommandWorker.expired?(%{expires_at: now})
    end
  end
end
