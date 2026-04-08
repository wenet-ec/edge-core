# edge_agent/test/edge_agent_web/controllers/command_execution_json_test.exs
defmodule EdgeAgentWeb.Controllers.CommandExecutionJSONTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgentWeb.Controllers.CommandExecutionJSON

  @valid_id "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  @valid_command_id "11111111-2222-3333-4444-555555555555"
  @valid_node_id "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"

  defp build_execution(overrides \\ %{}) do
    struct(
      CommandExecution,
      Map.merge(
        %{
          id: @valid_id,
          command_id: @valid_command_id,
          node_id: @valid_node_id,
          command_text: "uptime",
          timeout: 30_000,
          expired_at: nil,
          status: "pending",
          output: nil,
          exit_code: nil,
          inserted_at: ~U[2026-01-01 00:00:00Z],
          updated_at: ~U[2026-01-01 00:00:00Z]
        },
        overrides
      )
    )
  end

  describe "show/1" do
    test "wraps data under :data key" do
      result = CommandExecutionJSON.show(%{command_execution: build_execution()})
      assert Map.has_key?(result, :data)
    end

    test "all fields are present" do
      %{data: data} = CommandExecutionJSON.show(%{command_execution: build_execution()})

      for field <- [
            :id,
            :command_id,
            :node_id,
            :command_text,
            :timeout,
            :expired_at,
            :status,
            :output,
            :exit_code,
            :inserted_at,
            :updated_at
          ] do
        assert Map.has_key?(data, field), "missing field: #{field}"
      end
    end

    test "nil expired_at is included" do
      %{data: data} = CommandExecutionJSON.show(%{command_execution: build_execution()})
      assert Map.has_key?(data, :expired_at)
      assert data.expired_at == nil
    end

    test "expired_at is passed through when set" do
      exec = build_execution(%{expired_at: ~U[2026-12-31 00:00:00Z]})
      %{data: data} = CommandExecutionJSON.show(%{command_execution: exec})
      assert data.expired_at == ~U[2026-12-31 00:00:00Z]
    end

    test "scalar values are passed through correctly" do
      execution =
        build_execution(%{
          status: "completed",
          output: "load average: 0.1",
          exit_code: 0,
          timeout: 5_000
        })

      %{data: data} = CommandExecutionJSON.show(%{command_execution: execution})
      assert data.id == @valid_id
      assert data.command_id == @valid_command_id
      assert data.node_id == @valid_node_id
      assert data.command_text == "uptime"
      assert data.status == "completed"
      assert data.output == "load average: 0.1"
      assert data.exit_code == 0
      assert data.timeout == 5_000
    end

    test "nil output and exit_code are included (not excluded)" do
      %{data: data} = CommandExecutionJSON.show(%{command_execution: build_execution()})
      assert Map.has_key?(data, :output)
      assert Map.has_key?(data, :exit_code)
      assert data.output == nil
      assert data.exit_code == nil
    end

    test "timestamps are passed through" do
      %{data: data} = CommandExecutionJSON.show(%{command_execution: build_execution()})
      assert data.inserted_at == ~U[2026-01-01 00:00:00Z]
      assert data.updated_at == ~U[2026-01-01 00:00:00Z]
    end
  end

  describe "cancel/1" do
    test "wraps result under :data key" do
      result = CommandExecutionJSON.cancel(%{result: %{status: "cancelled"}})
      assert Map.has_key?(result, :data)
    end

    test "result map is passed through unchanged" do
      payload = %{status: "cancelled", message: "execution cancelled"}
      %{data: data} = CommandExecutionJSON.cancel(%{result: payload})
      assert data == payload
    end

    test "any map is preserved" do
      payload = %{foo: "bar", count: 42}
      %{data: data} = CommandExecutionJSON.cancel(%{result: payload})
      assert data == payload
    end
  end
end
