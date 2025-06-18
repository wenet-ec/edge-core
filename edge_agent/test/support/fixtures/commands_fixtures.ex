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
      attrs
      |> Enum.into(%{
        command_id: "7488a646-e31f-11e4-aace-600308960662",
        node_id: "7488a646-e31f-11e4-aace-600308960662",
        command_text: "echo hello",
        status: "pending",
        output: "some output",
        exit_code: 0
      })
      |> EdgeAgent.Commands.create_command_execution()

    command_execution
  end
end
