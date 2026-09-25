# edge_agent/test/support/fixtures.ex
defmodule EdgeAgent.Test.Fixtures do
  @moduledoc "Shared database fixtures for Agent tests."

  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Repo

  @spec insert_command_execution!(map()) :: CommandExecution.t()
  def insert_command_execution!(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      command_id: Ecto.UUID.generate(),
      node_id: Ecto.UUID.generate(),
      command_text: "uptime"
    }

    %CommandExecution{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
