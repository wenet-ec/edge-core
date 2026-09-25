# edge_admin/test/edge_admin/commands/filters/command_filters_test.exs
defmodule EdgeAdmin.Commands.Filters.CommandFiltersTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Commands.Filters.CommandFilters
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Test.Fixtures

  defp insert_command(overrides \\ %{}) do
    Fixtures.insert_command!(overrides)
  end

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()
  # apply_has_timeout/2 — virtual boolean: timeout IS [NOT] NULL

  describe "apply_has_timeout/2" do
    test "true matches commands with a non-null timeout" do
      with_timeout = insert_command(%{timeout: 30_000})
      _without_timeout = insert_command(%{timeout: nil})

      query = CommandFilters.apply_has_timeout(Command, [%{op: :==, value: true}])

      assert ids(query) == [with_timeout.id]
    end

    test "false matches commands with a null timeout" do
      _with_timeout = insert_command(%{timeout: 30_000})
      without_timeout = insert_command(%{timeout: nil})

      query = CommandFilters.apply_has_timeout(Command, [%{op: :==, value: false}])

      assert ids(query) == [without_timeout.id]
    end

    test "string 'true' / 'false' are ignored" do
      with_timeout = insert_command(%{timeout: 30_000})
      without_timeout = insert_command(%{timeout: nil})

      assert ids(CommandFilters.apply_has_timeout(Command, [%{op: :==, value: "true"}])) ==
               Enum.sort([with_timeout.id, without_timeout.id])

      assert ids(CommandFilters.apply_has_timeout(Command, [%{op: :==, value: "false"}])) ==
               Enum.sort([with_timeout.id, without_timeout.id])
    end

    test "no filters → query unchanged" do
      a = insert_command()
      b = insert_command()

      assert ids(CommandFilters.apply_has_timeout(Command, [])) == Enum.sort([a.id, b.id])
    end

    test "unrecognised filter shape is ignored (catch-all)" do
      a = insert_command()
      b = insert_command()

      query = CommandFilters.apply_has_timeout(Command, [%{op: :>, value: 5}])
      assert ids(query) == Enum.sort([a.id, b.id])
    end
  end

  # apply_has_expires_at/2 — virtual boolean: expires_at IS [NOT] NULL.
  # Critically, this does NOT check whether the timestamp is in the past.

  describe "apply_has_expires_at/2" do
    test "true matches commands with expires_at set, regardless of past/future" do
      past = ~U[2000-01-01 00:00:00Z]
      future = ~U[2099-01-01 00:00:00Z]

      past_key = insert_command(%{expires_at: past})
      future_key = insert_command(%{expires_at: future})
      _no_expiry = insert_command(%{expires_at: nil})

      query = CommandFilters.apply_has_expires_at(Command, [%{op: :==, value: true}])

      assert ids(query) == Enum.sort([past_key.id, future_key.id])
    end

    test "false matches commands with no expiry set" do
      future = ~U[2099-01-01 00:00:00Z]

      _has_expiry = insert_command(%{expires_at: future})
      no_expiry = insert_command(%{expires_at: nil})

      query = CommandFilters.apply_has_expires_at(Command, [%{op: :==, value: false}])

      assert ids(query) == [no_expiry.id]
    end

    test "string 'true' / 'false' are ignored" do
      future = ~U[2099-01-01 00:00:00Z]
      with_exp = insert_command(%{expires_at: future})
      without = insert_command(%{expires_at: nil})

      assert ids(CommandFilters.apply_has_expires_at(Command, [%{op: :==, value: "true"}])) ==
               Enum.sort([with_exp.id, without.id])

      assert ids(CommandFilters.apply_has_expires_at(Command, [%{op: :==, value: "false"}])) ==
               Enum.sort([with_exp.id, without.id])
    end

    test "no filters → query unchanged" do
      a = insert_command()
      b = insert_command()

      assert ids(CommandFilters.apply_has_expires_at(Command, [])) == Enum.sort([a.id, b.id])
    end
  end
end
