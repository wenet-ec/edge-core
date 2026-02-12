defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionJSONTest do
  use ExUnit.Case, async: true

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdminWeb.Controllers.Commands.CommandExecutionJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp bare_execution(overrides \\ %{}) do
    Map.merge(
      %CommandExecution{
        id: "exec-uuid-1",
        command_id: "cmd-uuid-1",
        node_id: "node-uuid-1",
        status: "pending",
        target_all: false,
        output: nil,
        exit_code: nil,
        sent_at: nil,
        completed_at: nil,
        inserted_at: @now,
        updated_at: @now,
        command: %NotLoaded{},
        cluster: %NotLoaded{}
      },
      overrides
    )
  end

  defp execution_with_assocs(command_text, timeout, cluster_name) do
    bare_execution(%{
      command: %{command_text: command_text, timeout: timeout},
      cluster: %{name: cluster_name}
    })
  end

  defp fake_meta(overrides \\ []) do
    struct(
      Flop.Meta,
      Keyword.merge(
        [
          current_page: 1,
          page_size: 20,
          total_count: 1,
          total_pages: 1,
          has_next_page?: false,
          has_previous_page?: false
        ],
        overrides
      )
    )
  end

  # -----------------------------------------------------------------------
  # show/1
  # -----------------------------------------------------------------------

  describe "show/1" do
    test "wraps execution in %{data: ...}" do
      result = CommandExecutionJSON.show(%{command_execution: bare_execution()})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      data = CommandExecutionJSON.show(%{command_execution: bare_execution()}).data
      # Note: timeout is NOT included in the admin-facing view (unlike the agent-facing view)
      expected = [
        :id,
        :command_id,
        :node_id,
        :cluster_name,
        :target_all,
        :status,
        :command_text,
        :output,
        :exit_code,
        :sent_at,
        :completed_at,
        :inserted_at,
        :updated_at
      ]

      for field <- expected, do: assert(Map.has_key?(data, field), "missing field: #{field}")
    end

    test "timeout is NOT exposed in the admin-facing view" do
      data = CommandExecutionJSON.show(%{command_execution: bare_execution()}).data
      refute Map.has_key?(data, :timeout)
    end

    test "scalar fields are passed through" do
      exec =
        bare_execution(%{
          status: "completed",
          target_all: true,
          output: "hello",
          exit_code: 0,
          sent_at: @now,
          completed_at: @now
        })

      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.id == "exec-uuid-1"
      assert data.command_id == "cmd-uuid-1"
      assert data.node_id == "node-uuid-1"
      assert data.status == "completed"
      assert data.target_all == true
      assert data.output == "hello"
      assert data.exit_code == 0
      assert data.sent_at == @now
      assert data.completed_at == @now
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end
  end

  # -----------------------------------------------------------------------
  # cluster_name delegation
  # -----------------------------------------------------------------------

  describe "cluster_name — cluster association loaded" do
    test "returns cluster name from loaded association" do
      exec = execution_with_assocs("ls", nil, "cluster-prod")
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.cluster_name == "cluster-prod"
    end
  end

  describe "cluster_name — cluster association not loaded" do
    test "returns nil when cluster is not preloaded" do
      exec = bare_execution()
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.cluster_name == nil
    end
  end

  # -----------------------------------------------------------------------
  # command_text delegation
  # -----------------------------------------------------------------------

  describe "command_text — not loaded" do
    test "nil when command not preloaded" do
      exec = bare_execution()
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.command_text == nil
    end
  end

  describe "command_text — loaded" do
    test "command_text from loaded command" do
      exec = execution_with_assocs("df -h", 3000, "cluster-dev")
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.command_text == "df -h"
    end
  end

  # -----------------------------------------------------------------------
  # cancel/1
  # -----------------------------------------------------------------------

  describe "cancel/1" do
    test "wraps result in %{data: result}" do
      result = CommandExecutionJSON.cancel(%{result: %{status: "cancelled"}})
      assert result == %{data: %{status: "cancelled"}}
    end

    test "passes result through unchanged" do
      payload = %{some: "map", with: 42}
      assert CommandExecutionJSON.cancel(%{result: payload}) == %{data: payload}
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — pagination renames
  # -----------------------------------------------------------------------

  describe "index/1 — pagination field renames from Flop.Meta" do
    test "current_page renamed to page" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(current_page: 2)})
      assert Map.has_key?(result.pagination, :page)
      refute Map.has_key?(result.pagination, :current_page)
      assert result.pagination.page == 2
    end

    test "total_count renamed to total" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(total_count: 99)})
      assert Map.has_key?(result.pagination, :total)
      refute Map.has_key?(result.pagination, :total_count)
      assert result.pagination.total == 99
    end

    test "has_next_page? renamed to has_next" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(has_next_page?: true)})
      assert Map.has_key?(result.pagination, :has_next)
      refute Map.has_key?(result.pagination, :has_next_page?)
      assert result.pagination.has_next == true
    end

    test "has_previous_page? renamed to has_prev" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(has_previous_page?: true)})
      assert Map.has_key?(result.pagination, :has_prev)
      refute Map.has_key?(result.pagination, :has_previous_page?)
      assert result.pagination.has_prev == true
    end

    test "pagination has exactly the expected keys" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.pagination)),
               MapSet.new([:page, :page_size, :total, :total_pages, :has_next, :has_prev])
             )
    end
  end

  describe "index/1 — data array" do
    test "empty list produces empty data" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta()})
      assert result.data == []
    end

    test "multiple executions rendered in order" do
      execs = [
        bare_execution(%{id: "uuid-1"}),
        bare_execution(%{id: "uuid-2"})
      ]

      result = CommandExecutionJSON.index(%{command_executions: execs, meta: fake_meta()})
      assert length(result.data) == 2
      assert Enum.map(result.data, & &1.id) == ["uuid-1", "uuid-2"]
    end
  end
end
