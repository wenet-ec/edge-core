# edge_admin/test/support/fixtures/commands_fixtures.ex
defmodule EdgeAdmin.CommandsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAdmin.Commands` context.
  """

  @doc """
  Generate a command.
  """
  def command_fixture(attrs \\ %{}) do
    {:ok, command} =
      attrs
      |> Enum.into(%{
        commands: ["option1", "option2"]
      })
      |> EdgeAdmin.Commands.create_command()

    command
  end
end
