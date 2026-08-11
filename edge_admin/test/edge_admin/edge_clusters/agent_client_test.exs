# edge_admin/test/edge_admin/edge_clusters/agent_client_test.exs
defmodule EdgeAdmin.EdgeClusters.AgentClientTest do
  use ExUnit.Case, async: false

  alias EdgeAdmin.EdgeClusters.AgentClient

  @keys [:command_delivery_timeout, :metrics_scrape_timeout, :health_check_timeout]

  setup do
    previous = Map.new(@keys, &{&1, Elixir.Application.get_env(:edge_admin, &1)})

    Elixir.Application.put_env(:edge_admin, :command_delivery_timeout, 11_000)
    Elixir.Application.put_env(:edge_admin, :metrics_scrape_timeout, 7_000)
    Elixir.Application.put_env(:edge_admin, :health_check_timeout, 3_000)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Elixir.Application.delete_env(:edge_admin, key),
          else: Elixir.Application.put_env(:edge_admin, key, value)
      end)
    end)

    :ok
  end

  test "derives command and metrics call timeouts from their transport timeouts" do
    assert AgentClient.command_call_timeout() == 13_000
    assert AgentClient.metrics_call_timeout() == 9_000
  end

  test "derives health and diagnostics call timeouts from health timeout" do
    assert AgentClient.health_check_call_timeout() == 3_500
    assert AgentClient.diagnostics_call_timeout() == 5_000
  end
end
