defmodule EdgeAdminWeb.Controllers.Commands.CommandJSONTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdminWeb.Controllers.Commands.CommandJSON

  @now ~U[2026-01-01 10:00:00Z]

  defp fake_command(overrides \\ %{}) do
    Map.merge(
      %Command{
        id: "cmd-uuid-1",
        command_text: "echo hello",
        timeout: nil,
        targeting: %{"type" => "all"},
        inserted_at: @now,
        updated_at: @now
      },
      overrides
    )
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
    test "wraps command in %{data: ...}" do
      result = CommandJSON.show(%{command: fake_command()})
      assert Map.has_key?(result, :data)
    end

    test "data contains all required fields" do
      data = CommandJSON.show(%{command: fake_command()}).data
      assert Map.has_key?(data, :id)
      assert Map.has_key?(data, :command_text)
      assert Map.has_key?(data, :timeout)
      assert Map.has_key?(data, :targeting)
      assert Map.has_key?(data, :inserted_at)
      assert Map.has_key?(data, :updated_at)
    end

    test "field values are passed through correctly" do
      cmd = fake_command(%{command_text: "ls -la", timeout: 5000, targeting: %{"type" => "nodes"}})
      data = CommandJSON.show(%{command: cmd}).data
      assert data.id == "cmd-uuid-1"
      assert data.command_text == "ls -la"
      assert data.timeout == 5000
      assert data.targeting == %{"type" => "nodes"}
      assert data.inserted_at == @now
      assert data.updated_at == @now
    end

    test "nil timeout is passed through" do
      data = CommandJSON.show(%{command: fake_command(%{timeout: nil})}).data
      assert data.timeout == nil
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — data array
  # -----------------------------------------------------------------------

  describe "index/1 — data array" do
    test "result has :data and :pagination keys" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta()})
      assert Map.has_key?(result, :data)
      assert Map.has_key?(result, :pagination)
    end

    test "empty commands produces empty data list" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta()})
      assert result.data == []
    end

    test "each command is rendered via data/1" do
      cmd = fake_command(%{command_text: "pwd"})
      result = CommandJSON.index(%{commands: [cmd], meta: fake_meta()})
      assert length(result.data) == 1
      assert hd(result.data).command_text == "pwd"
    end

    test "multiple commands all rendered in order" do
      cmds = [
        fake_command(%{id: "uuid-1", command_text: "ls"}),
        fake_command(%{id: "uuid-2", command_text: "pwd"})
      ]

      result = CommandJSON.index(%{commands: cmds, meta: fake_meta()})
      assert length(result.data) == 2
      assert Enum.map(result.data, & &1.id) == ["uuid-1", "uuid-2"]
    end
  end

  # -----------------------------------------------------------------------
  # index/1 — pagination field renames (the critical part)
  # -----------------------------------------------------------------------

  describe "index/1 — pagination field renames from Flop.Meta" do
    test "current_page is renamed to page" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(current_page: 3)})
      assert Map.has_key?(result.pagination, :page)
      refute Map.has_key?(result.pagination, :current_page)
      assert result.pagination.page == 3
    end

    test "total_count is renamed to total" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(total_count: 42)})
      assert Map.has_key?(result.pagination, :total)
      refute Map.has_key?(result.pagination, :total_count)
      assert result.pagination.total == 42
    end

    test "has_next_page? is renamed to has_next (no question mark)" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(has_next_page?: true)})
      assert Map.has_key?(result.pagination, :has_next)
      refute Map.has_key?(result.pagination, :has_next_page?)
      assert result.pagination.has_next == true
    end

    test "has_previous_page? is renamed to has_prev (no question mark, shortened)" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(has_previous_page?: true)})
      assert Map.has_key?(result.pagination, :has_prev)
      refute Map.has_key?(result.pagination, :has_previous_page?)
      assert result.pagination.has_prev == true
    end

    test "page_size is passed through unchanged" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(page_size: 50)})
      assert result.pagination.page_size == 50
    end

    test "total_pages is passed through unchanged" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(total_pages: 7)})
      assert result.pagination.total_pages == 7
    end

    test "has_next false is preserved" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(has_next_page?: false)})
      assert result.pagination.has_next == false
    end

    test "has_prev false is preserved" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta(has_previous_page?: false)})
      assert result.pagination.has_prev == false
    end

    test "pagination has exactly the expected keys" do
      result = CommandJSON.index(%{commands: [], meta: fake_meta()})

      assert MapSet.equal?(
               MapSet.new(Map.keys(result.pagination)),
               MapSet.new([:page, :page_size, :total, :total_pages, :has_next, :has_prev])
             )
    end
  end
end
