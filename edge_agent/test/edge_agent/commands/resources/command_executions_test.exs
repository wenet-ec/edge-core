# edge_agent/test/edge_agent/commands/resources/command_executions_test.exs
defmodule EdgeAgent.Commands.Resources.CommandExecutionsTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.Commands.Resources.CommandExecutions
  alias EdgeAgent.Test.Fixtures

  test "reportable/0 returns completed and expired rows, excluding pending rows" do
    completed = Fixtures.insert_command_execution!(%{status: :completed})
    expired = Fixtures.insert_command_execution!(%{status: :expired})
    _pending = Fixtures.insert_command_execution!(%{status: :pending})

    reportable_ids = CommandExecutions.reportable() |> Enum.map(& &1.id) |> Enum.sort()

    assert reportable_ids == Enum.sort([completed.id, expired.id])
  end
end
