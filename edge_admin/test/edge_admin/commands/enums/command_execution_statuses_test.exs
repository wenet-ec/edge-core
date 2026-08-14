# edge_admin/test/edge_admin/commands/enums/command_execution_statuses_test.exs
defmodule EdgeAdmin.Commands.Enums.CommandExecutionStatusesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Enums.CommandExecutionStatuses

  test "statuses/0 returns all lifecycle statuses in canonical order" do
    assert CommandExecutionStatuses.statuses() == [:pending, :sent, :completed, :cancelled, :expired, :dropped]
  end

  test "terminal_statuses/0 returns statuses that cannot transition further" do
    assert CommandExecutionStatuses.terminal_statuses() == [:completed, :cancelled, :expired, :dropped]
  end

  test "cancellable_statuses/0 returns statuses that accept cancellation" do
    assert CommandExecutionStatuses.cancellable_statuses() == [:pending, :sent]
  end

  test "status_strings/0 mirrors statuses/0 in wire format" do
    assert CommandExecutionStatuses.status_strings() ==
             Enum.map(CommandExecutionStatuses.statuses(), &Atom.to_string/1)
  end
end
