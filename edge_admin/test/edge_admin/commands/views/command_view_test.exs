# edge_admin/test/edge_admin/commands/views/command_view_test.exs
defmodule EdgeAdmin.Commands.Views.CommandViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Views.CommandView

  defp command_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %Command{
      id: "command-uuid-1",
      command_text: "uname -a",
      timeout: 30_000,
      expires_at: nil,
      targeting: %{"type" => "all"},
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      command = command_fixture()

      result = CommandView.render(command)

      assert result.id == command.id
      assert result.command_text == "uname -a"
      assert result.timeout == 30_000
      assert result.expires_at == nil
      assert result.targeting == %{"type" => "all"}
      assert result.inserted_at == command.inserted_at
      assert result.updated_at == command.updated_at
    end

    test "preserves nil timeout / expires_at (no coercion)" do
      command = command_fixture(%{timeout: nil, expires_at: nil})

      result = CommandView.render(command)

      assert result.timeout == nil
      assert result.expires_at == nil
    end

    test "passes through targeting maps unchanged (string keys preserved)" do
      targeting = %{
        "type" => "clusters",
        "cluster_names" => ["prod"],
        "node_filters" => %{"status" => "healthy"}
      }

      command = command_fixture(%{targeting: targeting})

      assert CommandView.render(command).targeting == targeting
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = CommandView.render(command_fixture())

      expected_keys = Enum.sort(~w(id command_text timeout expires_at targeting inserted_at updated_at)a)
      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
