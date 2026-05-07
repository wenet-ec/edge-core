# edge_admin/test/edge_admin_web/live/quantum_dashboard_test.exs
defmodule EdgeAdminWeb.Live.QuantumDashboardTest do
  use ExUnit.Case, async: true

  alias EdgeAdminWeb.Live.QuantumDashboard

  # ---------------------------------------------------------------------------
  # humanize_ago/1 — non-negative seconds → past-tense relative string
  # ---------------------------------------------------------------------------

  describe "humanize_ago/1" do
    test "negative seconds → 'in the future' (clock skew safety)" do
      assert QuantumDashboard.humanize_ago(-1) == "in the future"
      assert QuantumDashboard.humanize_ago(-3600) == "in the future"
    end

    test "0..59 → seconds suffix" do
      assert QuantumDashboard.humanize_ago(0) == "0s ago"
      assert QuantumDashboard.humanize_ago(1) == "1s ago"
      assert QuantumDashboard.humanize_ago(59) == "59s ago"
    end

    test "60..3599 → minutes suffix (truncated)" do
      assert QuantumDashboard.humanize_ago(60) == "1m ago"
      assert QuantumDashboard.humanize_ago(119) == "1m ago"
      assert QuantumDashboard.humanize_ago(120) == "2m ago"
      assert QuantumDashboard.humanize_ago(3599) == "59m ago"
    end

    test "3600..86_399 → hours suffix" do
      assert QuantumDashboard.humanize_ago(3600) == "1h ago"
      assert QuantumDashboard.humanize_ago(7200) == "2h ago"
      assert QuantumDashboard.humanize_ago(86_399) == "23h ago"
    end

    test "≥ 86_400 → days suffix" do
      assert QuantumDashboard.humanize_ago(86_400) == "1d ago"
      assert QuantumDashboard.humanize_ago(86_400 * 5 + 1234) == "5d ago"
    end
  end

  # ---------------------------------------------------------------------------
  # humanize_in/1 — symmetric to humanize_ago/1, future-tense
  # ---------------------------------------------------------------------------

  describe "humanize_in/1" do
    test "non-positive seconds → 'now'" do
      assert QuantumDashboard.humanize_in(0) == "now"
      assert QuantumDashboard.humanize_in(-1) == "now"
      assert QuantumDashboard.humanize_in(-3600) == "now"
    end

    test "1..59 → 'in Ns'" do
      assert QuantumDashboard.humanize_in(1) == "in 1s"
      assert QuantumDashboard.humanize_in(59) == "in 59s"
    end

    test "60..3599 → 'in Nm'" do
      assert QuantumDashboard.humanize_in(60) == "in 1m"
      assert QuantumDashboard.humanize_in(3599) == "in 59m"
    end

    test "3600..86_399 → 'in Nh'" do
      assert QuantumDashboard.humanize_in(3600) == "in 1h"
      assert QuantumDashboard.humanize_in(86_399) == "in 23h"
    end

    test "≥ 86_400 → 'in Nd'" do
      assert QuantumDashboard.humanize_in(86_400) == "in 1d"
      assert QuantumDashboard.humanize_in(86_400 * 7) == "in 7d"
    end
  end

  # ---------------------------------------------------------------------------
  # format_duration/1 — native time units → "?", "<1ms", "Nms", or "N.Ns"
  # ---------------------------------------------------------------------------

  describe "format_duration/1" do
    test "nil → '?'" do
      assert QuantumDashboard.format_duration(nil) == "?"
    end

    test "sub-millisecond duration → '<1ms'" do
      # System.convert_time_unit(N, :native, :millisecond) yields 0 for very
      # small native counts. Use 0 directly to guarantee the <1ms branch.
      assert QuantumDashboard.format_duration(0) == "<1ms"
    end

    test "millisecond range → 'Nms' (no fractional part)" do
      ms = 250
      native = System.convert_time_unit(ms, :millisecond, :native)
      assert QuantumDashboard.format_duration(native) == "250ms"
    end

    test "exactly 1000ms boundary lands in the seconds branch" do
      native = System.convert_time_unit(1000, :millisecond, :native)
      # ms == 1000, not < 1000 → seconds branch.
      assert QuantumDashboard.format_duration(native) == "1.0s"
    end

    test "second range → 'N.Ns' rounded to 2dp" do
      native = System.convert_time_unit(1234, :millisecond, :native)
      assert QuantumDashboard.format_duration(native) == "1.23s"
    end

    test "large duration is still rendered in seconds" do
      native = System.convert_time_unit(60_000, :millisecond, :native)
      assert QuantumDashboard.format_duration(native) == "60.0s"
    end
  end

  # ---------------------------------------------------------------------------
  # format_task/1 — Quantum task tuple → "Module.function/arity"
  # ---------------------------------------------------------------------------

  describe "format_task/1" do
    test "{m, f, a} tuple → 'Module.function/arity'" do
      assert QuantumDashboard.format_task({Enum, :map, [:list, :fun]}) == "Enum.map/2"
      assert QuantumDashboard.format_task({String, :upcase, [:value]}) == "String.upcase/1"
    end

    test "anonymous function falls back to inspect" do
      result = QuantumDashboard.format_task(fn -> :ok end)
      assert is_binary(result)
      assert String.starts_with?(result, "#Function<")
    end

    test "unknown shape falls back to inspect" do
      assert QuantumDashboard.format_task(:not_a_task) == ":not_a_task"
      assert QuantumDashboard.format_task("string") == ~s("string")
    end
  end

  # ---------------------------------------------------------------------------
  # format_schedule/1 — Crontab expression → composed cron string; otherwise inspect
  # ---------------------------------------------------------------------------

  describe "format_schedule/1" do
    test "Crontab.CronExpression → composed cron string" do
      {:ok, expr} = Crontab.CronExpression.Parser.parse("*/5 * * * *")
      result = QuantumDashboard.format_schedule(expr)

      # Composer round-trips to a recognisable cron string. Don't pin the exact
      # spacing — Composer's normalisation is its concern, not ours.
      assert is_binary(result)
      assert result =~ "*/5"
    end

    test "non-Crontab schedule (e.g. interval ms) falls back to inspect" do
      # Some Quantum schedules are integers (intervals).
      assert QuantumDashboard.format_schedule(60_000) == "60000"
      assert QuantumDashboard.format_schedule(:weird_atom) == ":weird_atom"
    end
  end

  # ---------------------------------------------------------------------------
  # next_run_payload/1 — input shape → :dash | {:ok, map} | {:error, reason}
  # ---------------------------------------------------------------------------

  describe "next_run_payload/1" do
    test "inactive job → :dash" do
      assert QuantumDashboard.next_run_payload(%{state: :inactive}) == :dash
    end

    test "next_run_naive: nil → :dash" do
      assert QuantumDashboard.next_run_payload(%{next_run_naive: nil}) == :dash
    end

    test "next_run_naive: {:error, reason} → {:error, reason}" do
      assert QuantumDashboard.next_run_payload(%{next_run_naive: {:error, "boom"}}) ==
               {:error, "boom"}
    end

    test "next_run_naive: {:ok, naive, tz} → {:ok, %{iso, naive, rel}}" do
      future = NaiveDateTime.add(NaiveDateTime.utc_now(), 600, :second)

      assert {:ok, %{iso: iso, naive: naive_str, rel: rel}} =
               QuantumDashboard.next_run_payload(%{next_run_naive: {:ok, future, :utc}})

      # ISO is the UTC datetime stringified.
      assert is_binary(iso)
      assert iso =~ "T"
      assert String.ends_with?(iso, "Z")

      # naive_str is the second-truncated naive form — matches NaiveDateTime.to_string
      # of the truncated value.
      assert naive_str == NaiveDateTime.to_string(NaiveDateTime.truncate(future, :second))

      # rel is humanize_in/1 of the seconds delta — for a 10-min-future time
      # this lands in the minutes range.
      assert rel == "in 10m"
    end

    test "unexpected shape → {:error, descriptive message}" do
      assert {:error, msg} = QuantumDashboard.next_run_payload(%{state: :something_else})
      assert msg =~ "unexpected next_run shape"
    end
  end

  # ---------------------------------------------------------------------------
  # next_run_class/1 — input shape → CSS class
  # ---------------------------------------------------------------------------

  describe "next_run_class/1" do
    test "inactive job → 'text-muted'" do
      assert QuantumDashboard.next_run_class(%{state: :inactive}) == "text-muted"
    end

    test "next_run_naive: nil → 'text-muted'" do
      assert QuantumDashboard.next_run_class(%{next_run_naive: nil}) == "text-muted"
    end

    test "next_run_naive: error → 'next-run-error'" do
      assert QuantumDashboard.next_run_class(%{next_run_naive: {:error, "x"}}) ==
               "next-run-error"
    end

    test "next run within 30 minutes → 'next-run-soon'" do
      soon = NaiveDateTime.add(NaiveDateTime.utc_now(), 600, :second)

      assert QuantumDashboard.next_run_class(%{next_run_naive: {:ok, soon, :utc}}) ==
               "next-run-soon"
    end

    test "next run at the 30-minute boundary → 'next-run-soon' (≤, not <)" do
      at_boundary = NaiveDateTime.add(NaiveDateTime.utc_now(), 1800, :second)

      # NaiveDateTime.diff truncates fractional seconds; subtract one to dodge
      # the rare case where a few microseconds tick past during the test.
      at_boundary_safe = NaiveDateTime.add(at_boundary, -1, :second)

      assert QuantumDashboard.next_run_class(%{next_run_naive: {:ok, at_boundary_safe, :utc}}) ==
               "next-run-soon"
    end

    test "next run more than 30 minutes out → '' (default)" do
      far = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600, :second)

      assert QuantumDashboard.next_run_class(%{next_run_naive: {:ok, far, :utc}}) == ""
    end

    test "next run already in the past → 'next-run-soon' (negative seconds <= 30min)" do
      past = NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second)

      assert QuantumDashboard.next_run_class(%{next_run_naive: {:ok, past, :utc}}) ==
               "next-run-soon"
    end
  end
end
