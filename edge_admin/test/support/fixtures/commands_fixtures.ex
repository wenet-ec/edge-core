# edge_admin/test/support/fixtures/commands_fixtures.ex
defmodule EdgeAdmin.CommandsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EdgeAdmin.Commands` context.
  """

  alias EdgeAdmin.Commands
  import EdgeAdmin.NodesFixtures

  @doc """
  Generate a command.
  """
  def command_fixture(attrs \\ %{}) do
    {:ok, command} =
      attrs
      |> Enum.into(%{
        # More realistic multi-line command text
        command_text: "echo 'hello'\nls -la\npwd"
      })
      |> Commands.create_command()

    command
  end

  @doc """
  Generate a command_execution.
  """
  def command_execution_fixture(attrs \\ %{}) do
    # Create dependencies first unless provided
    command = attrs[:command] || command_fixture()
    node = attrs[:node] || node_fixture()

    # Remove command/node from attrs if they were passed as structs
    attrs = Map.drop(attrs, [:command, :node])

    {:ok, command_execution} =
      attrs
      |> Enum.into(%{
        command_id: command.id,
        node_id: node.id,
        status: "pending",
        target_all: false,
        output: nil,
        exit_code: nil,
        sent_at: nil,
        completed_at: nil
      })
      |> Commands.create_command_execution()

    command_execution
  end

  @doc """
  Generate a completed command_execution for testing results.
  """
  def completed_command_execution_fixture(attrs \\ %{}) do
    command_execution_fixture(
      Map.merge(
        %{
          status: "completed",
          output:
            "$ echo 'hello'\nhello\n$ ls -la\ntotal 8\ndrwxr-xr-x 2 user user 4096 Jun 17 10:30 .\n$ pwd\n/home/user",
          exit_code: 0,
          sent_at: ~U[2025-06-16 02:07:00Z],
          completed_at: ~U[2025-06-16 02:08:00Z]
        },
        attrs
      )
    )
  end

  @doc """
  Generate a target_all command execution.
  """
  def target_all_execution_fixture(attrs \\ %{}) do
    command_execution_fixture(
      Map.merge(
        %{
          node_id: nil,
          target_all: true,
          status: "pending"
        },
        attrs
      )
    )
  end

  @doc """
  Generate a sent command execution.
  """
  def sent_command_execution_fixture(attrs \\ %{}) do
    command_execution_fixture(
      Map.merge(
        %{
          status: "sent",
          sent_at: ~U[2025-06-16 02:07:00Z]
        },
        attrs
      )
    )
  end
end
