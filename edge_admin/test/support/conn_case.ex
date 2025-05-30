# test/support/conn_case.ex
defmodule EdgeAdminWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint EdgeAdminWeb.Endpoint

      # Add verified routes support - THIS WAS MISSING
      use EdgeAdminWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EdgeAdminWeb.ConnCase

      # Add factory support for easier testing
      import EdgeAdmin.Factory
    end
  end

  setup tags do
    EdgeAdmin.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
