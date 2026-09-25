# edge_admin/test/edge_admin/commands/enums/command_execution_statuses_test.exs
defmodule EdgeAdmin.Commands.Enums.CommandExecutionStatusesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Enums.CommandExecutionStatuses

  @admin_completed_at ~U[2026-09-25 00:00:00Z]

  test "statuses/0 returns all lifecycle statuses in canonical order" do
    assert CommandExecutionStatuses.statuses() == [:pending, :sent, :completed, :cancelled, :expired, :dropped]
  end

  test "finalized?/2 applies the complete execution finalization rule" do
    assert CommandExecutionStatuses.finalized?(:completed, nil)
    assert CommandExecutionStatuses.finalized?(:dropped, nil)
    assert CommandExecutionStatuses.finalized?(:cancelled, @admin_completed_at)
    assert CommandExecutionStatuses.finalized?(:expired, @admin_completed_at)

    refute CommandExecutionStatuses.finalized?(:cancelled, nil)
    refute CommandExecutionStatuses.finalized?(:expired, nil)
    refute CommandExecutionStatuses.finalized?(:pending, nil)
    refute CommandExecutionStatuses.finalized?(:sent, nil)
  end

  test "cancellable_statuses/0 returns statuses that accept cancellation" do
    assert CommandExecutionStatuses.cancellable_statuses() == [:pending, :sent]
  end

  test "status_strings/0 mirrors statuses/0 in wire format" do
    assert CommandExecutionStatuses.status_strings() ==
             Enum.map(CommandExecutionStatuses.statuses(), &Atom.to_string/1)
  end
end
