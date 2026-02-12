defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionJSONTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdminWeb.Controllers.Agents.CommandExecutionJSON

  @now ~U[2026-01-01 10:00:00Z]

  # Minimal execution struct — no associations loaded
  defp bare_execution(overrides \\ %{}) do
    Map.merge(
      %CommandExecution{
        id: "exec-uuid-1",
        command_id: "cmd-uuid-1",
        status: "pending",
        inserted_at: @now,
        command: %Ecto.Association.NotLoaded{}
      },
      overrides
    )
  end

  # Execution with command association loaded
  defp execution_with_command(command_text, timeout) do
    bare_execution(%{
      command: %{command_text: command_text, timeout: timeout}
    })
  end

  defp fake_meta(overrides \\ %{}) do
    Map.merge(
      %{
        current_page: 1,
        page_size: 100,
        total_pages: 1,
        total_count: 1,
        has_next_page?: false,
        has_previous_page?: false
      },
      overrides
    )
  end

  # -----------------------------------------------------------------------
  # show/1
  # -----------------------------------------------------------------------

  describe "show/1" do
    test "wraps execution in %{data: ...}" do
      exec = execution_with_command("echo hi", 5000)
      result = CommandExecutionJSON.show(%{command_execution: exec})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      exec = execution_with_command("echo hi", 5000)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert Map.has_key?(data, :id)
      assert Map.has_key?(data, :command_id)
      assert Map.has_key?(data, :command_text)
      assert Map.has_key?(data, :timeout)
      assert Map.has_key?(data, :status)
      assert Map.has_key?(data, :inserted_at)
    end

    test "id and command_id are passed through" do
      exec = execution_with_command("ls -la", nil)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.id == "exec-uuid-1"
      assert data.command_id == "cmd-uuid-1"
    end

    test "status is passed through" do
      exec = "ls" |> execution_with_command(nil) |> Map.put(:status, "sent")
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.status == "sent"
    end

    test "inserted_at is passed through" do
      exec = execution_with_command("ls", nil)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.inserted_at == @now
    end
  end

  # -----------------------------------------------------------------------
  # data/1 — command_text delegation
  # -----------------------------------------------------------------------

  describe "command_text — command association loaded" do
    test "returns command_text from loaded command" do
      exec = execution_with_command("echo hello", 3000)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.command_text == "echo hello"
    end

    test "returns nil command_text when command has nil text" do
      exec = execution_with_command(nil, nil)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.command_text == nil
    end
  end

  describe "command_text — command association not loaded" do
    test "returns nil when command is not preloaded" do
      exec = bare_execution()
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.command_text == nil
    end
  end

  # -----------------------------------------------------------------------
  # data/1 — timeout delegation
  # -----------------------------------------------------------------------

  describe "timeout — command association loaded" do
    test "returns timeout from loaded command" do
      exec = execution_with_command("sleep 1", 5000)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.timeout == 5000
    end

    test "returns nil when command has no timeout" do
      exec = execution_with_command("ls", nil)
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.timeout == nil
    end
  end

  describe "timeout — command association not loaded" do
    test "returns nil when command is not preloaded" do
      exec = bare_execution()
      data = CommandExecutionJSON.show(%{command_execution: exec}).data
      assert data.timeout == nil
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — data array
  # -----------------------------------------------------------------------

  describe "index/1 — data array" do
    test "wraps list in %{data: [...], meta: ...}" do
      exec = execution_with_command("ls", nil)
      result = CommandExecutionJSON.index(%{command_executions: [exec], meta: fake_meta()})
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :meta)
    end

    test "data is a list" do
      exec = execution_with_command("ls", nil)
      result = CommandExecutionJSON.index(%{command_executions: [exec], meta: fake_meta()})
      assert is_list(result.data)
    end

    test "each item in data has required fields" do
      exec = execution_with_command("ls", nil)
      result = CommandExecutionJSON.index(%{command_executions: [exec], meta: fake_meta()})
      item = hd(result.data)
      assert Map.has_key?(item, :id)
      assert Map.has_key?(item, :command_id)
      assert Map.has_key?(item, :command_text)
      assert Map.has_key?(item, :timeout)
      assert Map.has_key?(item, :status)
      assert Map.has_key?(item, :inserted_at)
    end

    test "empty list produces empty data array" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{total_count: 0})})
      assert result.data == []
    end

    test "multiple executions all rendered" do
      exec1 = bare_execution(%{id: "uuid-1", command: %{command_text: "ls", timeout: nil}})
      exec2 = bare_execution(%{id: "uuid-2", command: %{command_text: "pwd", timeout: 1000}})
      result = CommandExecutionJSON.index(%{command_executions: [exec1, exec2], meta: fake_meta(%{total_count: 2})})
      assert length(result.data) == 2
      assert Enum.map(result.data, & &1.id) == ["uuid-1", "uuid-2"]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — meta field renames (the critical part)
  # -----------------------------------------------------------------------

  describe "index/1 — meta field renames" do
    test "has_next_page? is renamed to has_next_page (no question mark)" do
      meta = fake_meta(%{has_next_page?: true})
      result = CommandExecutionJSON.index(%{command_executions: [], meta: meta})
      assert Map.has_key?(result.meta, :has_next_page)
      refute Map.has_key?(result.meta, :has_next_page?)
    end

    test "has_previous_page? is renamed to has_previous_page (no question mark)" do
      meta = fake_meta(%{has_previous_page?: true})
      result = CommandExecutionJSON.index(%{command_executions: [], meta: meta})
      assert Map.has_key?(result.meta, :has_previous_page)
      refute Map.has_key?(result.meta, :has_previous_page?)
    end

    test "has_next_page value is preserved — true" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{has_next_page?: true})})
      assert result.meta.has_next_page == true
    end

    test "has_next_page value is preserved — false" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{has_next_page?: false})})
      assert result.meta.has_next_page == false
    end

    test "has_previous_page value is preserved — true" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{has_previous_page?: true})})
      assert result.meta.has_previous_page == true
    end

    test "has_previous_page value is preserved — false" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{has_previous_page?: false})})
      assert result.meta.has_previous_page == false
    end

    test "current_page passed through" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{current_page: 3})})
      assert result.meta.current_page == 3
    end

    test "page_size passed through" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{page_size: 50})})
      assert result.meta.page_size == 50
    end

    test "total_pages passed through" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{total_pages: 7})})
      assert result.meta.total_pages == 7
    end

    test "total_count passed through" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta(%{total_count: 42})})
      assert result.meta.total_count == 42
    end

    test "meta has exactly the expected keys" do
      result = CommandExecutionJSON.index(%{command_executions: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.meta)),
               MapSet.new([:current_page, :page_size, :total_pages, :total_count, :has_next_page, :has_previous_page])
             )
    end
  end
end
