# edge_agent/test/support/channel_case.ex
defmodule EdgeAgentWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import EdgeAgent.Factory
      import Phoenix.ChannelTest

      @endpoint EdgeAgentWeb.Endpoint
    end
  end

  setup tags do
    EdgeAgent.DataCase.setup_sandbox(tags)
    :ok
  end
end
