# edge_agent/test/edge_agent/self_updates/self_updates_test.exs
defmodule EdgeAgent.SelfUpdatesTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.SelfUpdates

  # ---------------------------------------------------------------------------
  # should_trigger_update?/2 — safety-relevant. A wrong decision either
  # restart-loops the container (false positive) or skips a real self-update
  # (false negative).
  # ---------------------------------------------------------------------------

  describe "should_trigger_update?/2" do
    test "nil inserted_at → false (refuses to act on bad/missing admin data)" do
      now = DateTime.utc_now()

      refute SelfUpdates.should_trigger_update?(nil, now)
      refute SelfUpdates.should_trigger_update?(nil, nil)
    end

    test "nil last_check → true (fresh agent picks up outstanding requests)" do
      assert SelfUpdates.should_trigger_update?(DateTime.utc_now(), nil)
    end

    test "inserted_at strictly newer than last_check → true" do
      last_check = DateTime.utc_now()
      newer = DateTime.add(last_check, 60, :second)

      assert SelfUpdates.should_trigger_update?(newer, last_check)
    end

    test "inserted_at equal to last_check → false (avoids re-triggering on same request)" do
      # DateTime.after? is strict — equal is not after. This is the
      # documented contract: don't re-trigger on the same request we
      # already processed.
      now = DateTime.truncate(DateTime.utc_now(), :second)

      refute SelfUpdates.should_trigger_update?(now, now)
    end

    test "inserted_at older than last_check → false" do
      last_check = DateTime.utc_now()
      older = DateTime.add(last_check, -60, :second)

      refute SelfUpdates.should_trigger_update?(older, last_check)
    end
  end

  # ---------------------------------------------------------------------------
  # parse_datetime/1 — explicitly returns nil (not "now" or raise) on bad
  # input so the upstream decision can refuse rather than guess.
  # ---------------------------------------------------------------------------

  describe "parse_datetime/1" do
    test "parses a valid ISO 8601 UTC datetime" do
      assert %DateTime{} = result = SelfUpdates.parse_datetime("2026-04-13T10:00:00Z")
      assert result.year == 2026
      assert result.month == 4
      assert result.day == 13
      assert result.hour == 10
      assert result.time_zone == "Etc/UTC"
    end

    test "parses a datetime with a non-Z UTC offset" do
      assert %DateTime{} = SelfUpdates.parse_datetime("2026-04-13T12:00:00+02:00")
    end

    test "nil input → nil (no parse attempted)" do
      assert SelfUpdates.parse_datetime(nil) == nil
    end

    test "malformed string → nil (refuses to act on bad data, doesn't raise)" do
      assert SelfUpdates.parse_datetime("not a date") == nil
      assert SelfUpdates.parse_datetime("") == nil
      assert SelfUpdates.parse_datetime("2026-13-99T99:99:99Z") == nil
    end

    test "date-only string → nil (we want full datetime, not date)" do
      # DateTime.from_iso8601 rejects date-only strings. Document the
      # contract: this function expects a full datetime, never falls back
      # to start-of-day.
      assert SelfUpdates.parse_datetime("2026-04-13") == nil
    end
  end
end
