# edge_agent/test/support/fixtures/commands_fixtures.ex
defmodule EdgeAgent.CommandsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAgent.Commands` context.
  """

  @doc """
  Generate a command_execution.
  """
  def command_execution_fixture(attrs \\ %{}) do
    {:ok, command_execution} =
      %{
        id: Ecto.UUID.generate(),
        command_id: Ecto.UUID.generate(),
        node_id: Ecto.UUID.generate(),
        command_text: "echo test",
        status: "pending"
      }
      |> Map.merge(attrs)
      |> EdgeAgent.Commands.create_command_execution()

    command_execution
  end
end
