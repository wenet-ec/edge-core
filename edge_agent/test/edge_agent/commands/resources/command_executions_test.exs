# edge_agent/test/edge_agent/commands/resources/command_executions_test.exs
defmodule EdgeAgent.Commands.Resources.CommandExecutionsTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.Commands.Resources.CommandExecutions
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Repo

  test "reportable/0 returns completed and expired rows, excluding pending rows" do
    completed = insert_execution(:completed)
    expired = insert_execution(:expired)
    _pending = insert_execution(:pending)

    reportable_ids = CommandExecutions.reportable() |> Enum.map(& &1.id) |> Enum.sort()

    assert reportable_ids == Enum.sort([completed.id, expired.id])
  end

  defp insert_execution(status) do
    attrs = %{
      id: Ecto.UUID.generate(),
      command_id: Ecto.UUID.generate(),
      node_id: Ecto.UUID.generate(),
      command_text: "uptime",
      status: status
    }

    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert!()
  end
end
