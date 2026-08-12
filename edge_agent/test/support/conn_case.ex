# edge_agent/test/support/conn_case.ex
defmodule EdgeAgentWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use EdgeAgentWeb, :verified_routes

      import EdgeAgent.Factory
      import EdgeAgentWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn

      @endpoint EdgeAgentWeb.Endpoint
    end
  end

  setup tags do
    EdgeAgent.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
