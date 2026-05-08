# edge_agent/test/edge_agent/vpn/derp_map_cache_test.exs
defmodule EdgeAgent.Vpn.DerpMapCacheTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Vpn.DerpMapCache

  # ---------------------------------------------------------------------------
  # next_state/4 — pure interval-doubling decision separated from the impure
  # fetch path. Operationally meaningful: too aggressive spams the map
  # server, too slow starves the agent of map updates.
  # ---------------------------------------------------------------------------

  describe "next_state/4 — failure (fetch returned nil)" do
    test "doubles the current interval, keeps the previous map" do
      assert DerpMapCache.next_state(nil, %{"prev" => "data"}, 5_000, 300_000) ==
               {%{"prev" => "data"}, 10_000}
    end

    test "doubling caps at stable_ms" do
      # 200_000 * 2 = 400_000 > 300_000 → capped at 300_000.
      assert DerpMapCache.next_state(nil, nil, 200_000, 300_000) == {nil, 300_000}
    end

    test "interval already at stable_ms stays at stable_ms" do
      assert DerpMapCache.next_state(nil, nil, 300_000, 300_000) == {nil, 300_000}
    end

    test "warmup ramp: 5s → 10s → 20s → ... up to stable" do
      # Walk through the documented ramp.
      ramp =
        Stream.iterate(5_000, fn current ->
          {nil, next} = DerpMapCache.next_state(nil, nil, current, 300_000)
          next
        end)

      observed = Enum.take(ramp, 7)
      assert observed == [5_000, 10_000, 20_000, 40_000, 80_000, 160_000, 300_000]
    end

    test "first failed fetch from a fresh agent (current_map nil) keeps map nil" do
      assert DerpMapCache.next_state(nil, nil, 5_000, 300_000) == {nil, 10_000}
    end
  end

  describe "next_state/4 — success (fetch returned a map)" do
    test "jumps straight to stable_ms regardless of current_ms" do
      new_map = %{"Regions" => %{"1" => %{}}}

      # From any starting interval, success → stable.
      assert DerpMapCache.next_state(new_map, nil, 5_000, 300_000) == {new_map, 300_000}
      assert DerpMapCache.next_state(new_map, nil, 80_000, 300_000) == {new_map, 300_000}
      assert DerpMapCache.next_state(new_map, nil, 300_000, 300_000) == {new_map, 300_000}
    end

    test "replaces the previous map (caller stops serving stale data)" do
      old = %{"Regions" => %{"old" => %{}}}
      new = %{"Regions" => %{"new" => %{}}}

      assert {result_map, _} = DerpMapCache.next_state(new, old, 80_000, 300_000)
      assert result_map == new
    end

    test "ignores current_ms entirely on success" do
      new = %{"Regions" => %{"r" => %{}}}

      # Current interval doesn't matter; success always jumps to stable.
      for current <- [1_000, 5_000, 50_000, 1_000_000] do
        assert DerpMapCache.next_state(new, nil, current, 300_000) == {new, 300_000}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # map_has_regions?/1 — what counts as a 'successful' DERP map. Empty or
  # missing Regions means the map server has nothing to overlay; treat as
  # failure so the warmup logic keeps retrying.
  # ---------------------------------------------------------------------------

  describe "map_has_regions?/1" do
    test "true when Regions map has at least one entry" do
      assert DerpMapCache.map_has_regions?(%{"Regions" => %{"1" => %{}}})
      assert DerpMapCache.map_has_regions?(%{"Regions" => %{"1" => %{}, "2" => %{}}})
    end

    test "false when Regions is an empty map" do
      refute DerpMapCache.map_has_regions?(%{"Regions" => %{}})
    end

    test "false when Regions key is missing" do
      refute DerpMapCache.map_has_regions?(%{"OtherKey" => "value"})
      refute DerpMapCache.map_has_regions?(%{})
    end

    test "false for non-map inputs" do
      refute DerpMapCache.map_has_regions?(nil)
      refute DerpMapCache.map_has_regions?("string")
      refute DerpMapCache.map_has_regions?([])
    end

    test "false when Regions is a non-map (defensive)" do
      # If a misbehaving map server returns Regions as a list or string,
      # fall through to the catch-all rather than crashing.
      refute DerpMapCache.map_has_regions?(%{"Regions" => []})
      refute DerpMapCache.map_has_regions?(%{"Regions" => "not a map"})
    end
  end
end
