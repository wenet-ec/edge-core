# edge_agent/test/support/data_case.ex
defmodule EdgeAgent.DataCase do
  @moduledoc """
  Test case for data-layer tests.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import EdgeAgent.Test.ChangesetAssertions

      alias EdgeAgent.Repo
    end
  end

  setup tags do
    EdgeAgent.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(EdgeAgent.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
