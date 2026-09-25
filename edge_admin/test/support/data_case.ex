# edge_admin/test/support/data_case.ex
defmodule EdgeAdmin.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  # Sandbox needs the real Ecto.Repo impl module (Postgres or SQLite),
  # not the dispatcher. Read at compile time from app env so the test
  # suite is mode-locked per test run (CI matrix runs each adapter).
  @repo_impl Application.compile_env!(:edge_admin, :repo_impl)

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      alias EdgeAdmin.Repo
    end
  end

  setup tags do
    EdgeAdmin.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(@repo_impl, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
